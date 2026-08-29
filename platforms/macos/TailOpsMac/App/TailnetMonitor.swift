import Foundation
import SwiftUI
import TailOpsCore
import TailOpsShared
import WidgetKit

@MainActor
final class TailnetMonitor: NSObject, ObservableObject {
    @Published private(set) var snapshot = TailnetSnapshot(hosts: [])
    @Published private(set) var actionConfiguration = TailnetActionConfiguration()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let statusProvider: TailscaleStatusProviding
    private let pingProvider: TailscalePingProviding?
    private let parser = TailnetSnapshotParser()
    private let tailnetStore: any TailnetStateStoring
    private let settingsStore: any TailOpsSettingsStoring
    private let requestStore: any TailOpsAppGroupRequestStoring
    private let actionCatalog = HostActionCatalog()
    private let maxRetainedPingSamples = 120
    private let pingDiagnosticsMinimumInterval: TimeInterval = 60 * 60
    private var automaticRefreshTask: Task<Void, Never>?
    private var lastPingDiagnosticsRefreshDate: Date?
    private var refreshRequestedWhileRefreshing = false

    init(
        statusProvider: TailscaleStatusProviding,
        pingProvider: TailscalePingProviding? = nil,
        tailnetStore: any TailnetStateStoring,
        settingsStore: any TailOpsSettingsStoring,
        requestStore: any TailOpsAppGroupRequestStoring,
        initialSnapshot: TailnetSnapshot? = nil
    ) {
        self.statusProvider = statusProvider
        self.pingProvider = pingProvider
        self.tailnetStore = tailnetStore
        self.settingsStore = settingsStore
        self.requestStore = requestStore
        super.init()
        if let initialSnapshot {
            snapshot = initialSnapshot
        } else if let stored = try? tailnetStore.load() {
            snapshot = stored
        }
        lastPingDiagnosticsRefreshDate = snapshot.hosts
            .compactMap { $0.diagnostics?.ping?.lastUpdated }
            .max()
        if let storedConfiguration = try? settingsStore.loadActionConfiguration() {
            actionConfiguration = storedConfiguration
        }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(refreshFromDistributedNotification),
            name: Notification.Name(TailOpsRefreshSignal.notificationName),
            object: nil
        )
    }

    deinit {
        automaticRefreshTask?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    var summary: TailnetSummary {
        TailnetSummary(hosts: snapshot.hosts)
    }

    var menuBarSymbol: String {
        switch summary.trafficLight {
        case .healthy:
            return "network"
        case .warning:
            return "exclamationmark.triangle"
        case .offline:
            return "wifi.slash"
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            refreshRequestedWhileRefreshing = true
            return
        }
        isRefreshing = true
        let attemptAt = Date()
        let previousHealth = try? tailnetStore.loadRefreshHealth()
        try? tailnetStore.saveRefreshHealth(TailOpsRefreshHealth(
            lastAttemptAt: attemptAt,
            lastSuccessAt: previousHealth?.lastSuccessAt
        ))
        WidgetCenter.shared.reloadTimelines(ofKind: "dev.tailops.monitor.widget")

        do {
            let data = try await statusProvider.statusJSON()
            let nextSnapshot = try parser.parse(data)
            let diagnosedSnapshot = await snapshotWithPingDiagnostics(nextSnapshot, now: Date())
            snapshot = diagnosedSnapshot
            lastError = nil
            try tailnetStore.save(diagnosedSnapshot)
            try tailnetStore.saveRefreshHealth(TailOpsRefreshHealth(
                lastAttemptAt: attemptAt,
                lastSuccessAt: Date()
            ))
            WidgetCenter.shared.reloadTimelines(ofKind: "dev.tailops.monitor.widget")
        } catch {
            lastError = error.localizedDescription
            try? tailnetStore.saveRefreshHealth(TailOpsRefreshHealth(
                lastAttemptAt: attemptAt,
                lastSuccessAt: previousHealth?.lastSuccessAt,
                lastError: error.localizedDescription
            ))
            WidgetCenter.shared.reloadTimelines(ofKind: "dev.tailops.monitor.widget")
        }

        isRefreshing = false
        if refreshRequestedWhileRefreshing {
            refreshRequestedWhileRefreshing = false
            await refresh()
        }
    }

    @discardableResult
    func refreshIfRequested() async -> Bool {
        guard (try? requestStore.loadRefreshRequest()) != nil else {
            return false
        }

        try? requestStore.clearRefreshRequest()
        await refresh()
        return true
    }

    func startAutomaticRefresh(every interval: Duration = .seconds(3600)) {
        guard automaticRefreshTask == nil else { return }

        automaticRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }

                await self?.refresh()
            }
        }
    }

    func actions(for host: TailnetHost) -> [HostAction] {
        HostActionCatalog(configuration: actionConfiguration).actions(for: host)
    }

    @objc private func refreshFromDistributedNotification(_ notification: Notification) {
        Task { @MainActor [weak self] in
            await self?.refreshIfRequested()
        }
    }

    private func snapshotWithPingDiagnostics(_ snapshot: TailnetSnapshot, now: Date) async -> TailnetSnapshot {
        guard let pingProvider else { return snapshot }

        let existingPingByHostID = Dictionary(
            uniqueKeysWithValues: self.snapshot.hosts.compactMap { host in
                host.diagnostics?.ping.map { (host.id, $0) }
            }
        )
        guard shouldRefreshPingDiagnostics(now: now) else {
            return snapshotWithRetainedPingDiagnostics(snapshot, existingPingByHostID: existingPingByHostID)
        }

        var diagnosedHosts: [TailnetHost] = []
        for host in snapshot.hosts {
            guard host.role == .peer, host.status == .online else {
                diagnosedHosts.append(host)
                continue
            }

            do {
                guard let ping = try await pingProvider.pingSummary(for: host) else {
                    diagnosedHosts.append(host)
                    continue
                }
                let retainedPing = existingPingByHostID[host.id]?.mergingRecentSamples(
                    from: ping,
                    maxSamples: maxRetainedPingSamples
                ) ?? ping
                diagnosedHosts.append(host.withDiagnostics(TailnetHostDiagnostics(ping: retainedPing)))
            } catch {
                diagnosedHosts.append(host)
            }
        }

        lastPingDiagnosticsRefreshDate = now
        return TailnetSnapshot(hosts: diagnosedHosts, generatedAt: snapshot.generatedAt)
    }

    private func shouldRefreshPingDiagnostics(now: Date) -> Bool {
        guard let lastPingDiagnosticsRefreshDate else { return true }
        return now.timeIntervalSince(lastPingDiagnosticsRefreshDate) >= pingDiagnosticsMinimumInterval
    }

    private func snapshotWithRetainedPingDiagnostics(
        _ snapshot: TailnetSnapshot,
        existingPingByHostID: [String: TailnetPingSummary]
    ) -> TailnetSnapshot {
        let hosts = snapshot.hosts.map { host in
            guard host.role == .peer,
                  host.status == .online,
                  let existingPing = existingPingByHostID[host.id]
            else {
                return host
            }

            return host.withDiagnostics(TailnetHostDiagnostics(ping: existingPing))
        }

        return TailnetSnapshot(hosts: hosts, generatedAt: snapshot.generatedAt)
    }
}
