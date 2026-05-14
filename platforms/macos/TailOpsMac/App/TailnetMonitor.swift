import Foundation
import SwiftUI
import TailOpsCore
import TailOpsShared
import WidgetKit

@MainActor
final class TailnetMonitor: ObservableObject {
    @Published private(set) var snapshot = TailnetSnapshot(hosts: [])
    @Published private(set) var actionConfiguration = TailnetActionConfiguration()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let statusProvider: TailscaleStatusProviding
    private let pingProvider: TailscalePingProviding?
    private let parser = TailnetSnapshotParser()
    private let snapshotStore: SharedSnapshotStoring
    private let actionCatalog = HostActionCatalog()
    private let maxRetainedPingSamples = 120

    init(
        statusProvider: TailscaleStatusProviding,
        pingProvider: TailscalePingProviding? = nil,
        snapshotStore: SharedSnapshotStoring,
        initialSnapshot: TailnetSnapshot? = nil
    ) {
        self.statusProvider = statusProvider
        self.pingProvider = pingProvider
        self.snapshotStore = snapshotStore
        if let initialSnapshot {
            snapshot = initialSnapshot
        } else if let stored = try? snapshotStore.load() {
            snapshot = stored
        }
        if let storedConfiguration = try? snapshotStore.loadActionConfiguration() {
            actionConfiguration = storedConfiguration
        }
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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let data = try await statusProvider.statusJSON()
            let nextSnapshot = try parser.parse(data)
            let diagnosedSnapshot = await snapshotWithPingDiagnostics(nextSnapshot)
            snapshot = diagnosedSnapshot
            lastError = nil
            try snapshotStore.save(diagnosedSnapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: "dev.tailops.monitor.widget")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func actions(for host: TailnetHost) -> [HostAction] {
        HostActionCatalog(configuration: actionConfiguration).actions(for: host)
    }

    private func snapshotWithPingDiagnostics(_ snapshot: TailnetSnapshot) async -> TailnetSnapshot {
        guard let pingProvider else { return snapshot }

        let existingPingByHostID = Dictionary(
            uniqueKeysWithValues: self.snapshot.hosts.compactMap { host in
                host.diagnostics?.ping.map { (host.id, $0) }
            }
        )
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

        return TailnetSnapshot(hosts: diagnosedHosts, generatedAt: snapshot.generatedAt)
    }
}
