import AppKit
import Foundation
import Network
import TailOpsCore
import TailOpsShared
import WidgetKit

@MainActor
final class TailnetMonitor: NSObject, ObservableObject {
    @Published private(set) var snapshot = TailnetSnapshot(hosts: [])
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let statusProvider: TailscaleStatusProviding
    private let pingProvider: TailscalePingProviding?
    private let parser = TailnetSnapshotParser()
    private let tailnetStore: any TailnetStateStoring
    private let requestStore: any TailOpsAppGroupRequestStoring
    private let maxRetainedPingSamples = 120
    private let maxConcurrentPings = 4
    private let pingDiagnosticsMinimumInterval: TimeInterval = 60 * 60
    private let systemEventRefreshDelay: Duration = .seconds(5)
    private let systemEventMinimumInterval: TimeInterval = 60
    private var automaticRefreshTask: Task<Void, Never>?
    private var systemEventRefreshTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var lastPingDiagnosticsRefreshDate: Date?
    private var lastRefreshDate: Date?
    private var refreshRequestedWhileRefreshing = false
    private var hasSeenInitialPath = false

    init(
        statusProvider: TailscaleStatusProviding,
        pingProvider: TailscalePingProviding? = nil,
        tailnetStore: any TailnetStateStoring,
        requestStore: any TailOpsAppGroupRequestStoring,
        initialSnapshot: TailnetSnapshot? = nil
    ) {
        self.statusProvider = statusProvider
        self.pingProvider = pingProvider
        self.tailnetStore = tailnetStore
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
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(refreshFromDistributedNotification),
            name: Notification.Name(TailOpsRefreshSignal.notificationName),
            object: nil
        )
    }

    deinit {
        automaticRefreshTask?.cancel()
        systemEventRefreshTask?.cancel()
        pathMonitor?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Publishes fresh Tailscale status first, then runs the hourly ping burst and
    /// publishes again, so the widget never waits on pings to show who is online.
    func refresh() async {
        guard !isRefreshing else {
            refreshRequestedWhileRefreshing = true
            return
        }
        isRefreshing = true
        let attemptAt = Date()
        lastRefreshDate = attemptAt
        let previousHealth = try? tailnetStore.loadRefreshHealth()
        try? tailnetStore.saveRefreshHealth(TailOpsRefreshHealth(
            lastAttemptAt: attemptAt,
            lastSuccessAt: previousHealth?.lastSuccessAt
        ))
        reloadWidget()

        do {
            let data = try await statusProvider.statusJSON()
            let parsed = try parser.parse(data)
            let previousPings = pingSummariesByHostID(in: snapshot)
            try publish(Self.snapshot(parsed, applying: previousPings))
            lastError = nil
            try tailnetStore.saveRefreshHealth(TailOpsRefreshHealth(
                lastAttemptAt: attemptAt,
                lastSuccessAt: Date()
            ))
            reloadWidget()

            if let pingProvider, shouldRefreshPingDiagnostics(now: Date()) {
                lastPingDiagnosticsRefreshDate = Date()
                let freshPings = await pingSummaries(for: parsed.hosts, using: pingProvider)
                let mergedPings = previousPings.merging(freshPings) { previous, fresh in
                    previous.mergingRecentSamples(from: fresh, maxSamples: maxRetainedPingSamples)
                }
                do {
                    try publish(Self.snapshot(parsed, applying: mergedPings))
                    reloadWidget()
                } catch {
                    NSLog("TailOps could not save ping diagnostics: %@", error.localizedDescription)
                }
            }
        } catch {
            lastError = error.localizedDescription
            try? tailnetStore.saveRefreshHealth(TailOpsRefreshHealth(
                lastAttemptAt: attemptAt,
                lastSuccessAt: previousHealth?.lastSuccessAt,
                lastError: error.localizedDescription
            ))
            reloadWidget()
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

    /// Refreshes shortly after the Mac wakes or its network path changes, since
    /// that is when peers most often appear or disappear. Bursts of events
    /// collapse into one refresh, at most once a minute.
    func startObservingSystemEvents() {
        guard pathMonitor == nil else { return }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.networkPathDidChange() }
        }
        monitor.start(queue: DispatchQueue(label: "dev.tailops.monitor.path"))
        pathMonitor = monitor
    }

    @objc private func refreshFromDistributedNotification(_ notification: Notification) {
        Task { @MainActor [weak self] in
            await self?.refreshIfRequested()
        }
    }

    @objc private func systemDidWake(_ notification: Notification) {
        scheduleSystemEventRefresh()
    }

    private func networkPathDidChange() {
        // The monitor reports the current path immediately; launch already refreshed.
        guard hasSeenInitialPath else {
            hasSeenInitialPath = true
            return
        }
        scheduleSystemEventRefresh()
    }

    private func scheduleSystemEventRefresh() {
        systemEventRefreshTask?.cancel()
        systemEventRefreshTask = Task { [weak self, systemEventRefreshDelay] in
            try? await Task.sleep(for: systemEventRefreshDelay)
            guard !Task.isCancelled, let self else { return }
            if let lastRefreshDate,
               Date().timeIntervalSince(lastRefreshDate) < systemEventMinimumInterval {
                return
            }
            await refresh()
        }
    }

    private func publish(_ nextSnapshot: TailnetSnapshot) throws {
        snapshot = nextSnapshot
        try tailnetStore.save(nextSnapshot)
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "dev.tailops.monitor.widget")
    }

    private func shouldRefreshPingDiagnostics(now: Date) -> Bool {
        guard let lastPingDiagnosticsRefreshDate else { return true }
        return now.timeIntervalSince(lastPingDiagnosticsRefreshDate) >= pingDiagnosticsMinimumInterval
    }

    private func pingSummariesByHostID(in snapshot: TailnetSnapshot) -> [String: TailnetPingSummary] {
        Dictionary(
            snapshot.hosts.compactMap { host in host.diagnostics?.ping.map { (host.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Pings online peers with bounded concurrency. A failed ping leaves that
    /// host out of the result so its earlier samples are kept.
    private func pingSummaries(
        for hosts: [TailnetHost],
        using pingProvider: TailscalePingProviding
    ) async -> [String: TailnetPingSummary] {
        var pending = hosts.filter { $0.role == .peer && $0.status == .online }[...]
        var summaries: [String: TailnetPingSummary] = [:]

        await withTaskGroup(of: (String, TailnetPingSummary?).self) { group in
            var running = 0
            while !pending.isEmpty || running > 0 {
                while running < maxConcurrentPings, let host = pending.popFirst() {
                    group.addTask { (host.id, try? await pingProvider.pingSummary(for: host)) }
                    running += 1
                }
                guard let (hostID, summary) = await group.next() else { break }
                running -= 1
                if let summary {
                    summaries[hostID] = summary
                }
            }
        }

        return summaries
    }

    /// Attaches ping history to online peers only; offline hosts and this device
    /// carry no ping diagnostics.
    private static func snapshot(
        _ snapshot: TailnetSnapshot,
        applying pingByHostID: [String: TailnetPingSummary]
    ) -> TailnetSnapshot {
        let hosts = snapshot.hosts.map { host in
            guard host.role == .peer,
                  host.status == .online,
                  let ping = pingByHostID[host.id]
            else {
                return host
            }

            return host.withDiagnostics(TailnetHostDiagnostics(ping: ping))
        }

        return snapshot.withHosts(hosts)
    }
}
