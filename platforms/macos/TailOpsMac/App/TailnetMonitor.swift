import AppKit
import Foundation
import Network
import TailOpsCore
import TailOpsShared

@MainActor
final class TailnetMonitor: NSObject, ObservableObject {
    @Published private(set) var snapshot = TailnetSnapshot(hosts: [])
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let statusProvider: TailscaleStatusProviding
    private let pingProvider: TailscalePingProviding?
    private let healthProvider: FleetHealthProviding?
    private let healthSources: @MainActor () -> [String]
    private let parser = TailnetSnapshotParser()
    private let tailnetStore: any TailnetStateStoring
    private let requestStore: any TailOpsAppGroupRequestStoring
    private let maxRetainedPingSamples = 120
    private let maxConcurrentPings = 4
    private let pingDiagnosticsMinimumInterval: TimeInterval = 60 * 60
    private let pingRetryInterval: TimeInterval = 10 * 60
    private let systemEventRefreshDelay: TimeInterval = 5
    private let systemEventMinimumInterval: TimeInterval = 60
    /// tailopsd writes every 15 minutes, so refresh that often while a health source is set.
    private let healthRefreshInterval: Duration = .seconds(15 * 60)
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
        healthProvider: FleetHealthProviding? = nil,
        healthSources: @escaping @MainActor () -> [String] = { [] },
        tailnetStore: any TailnetStateStoring,
        requestStore: any TailOpsAppGroupRequestStoring,
        initialSnapshot: TailnetSnapshot? = nil
    ) {
        self.statusProvider = statusProvider
        self.pingProvider = pingProvider
        self.healthProvider = healthProvider
        self.healthSources = healthSources
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
            let sources = healthProvider == nil ? [] : healthSources()
            let previousHealth = sources.isEmpty ? [] : snapshot.hosts.compactMap(\.health)
            try publish(Self.snapshot(parsed, applying: previousPings, health: previousHealth, at: Date()))
            lastError = nil
            try tailnetStore.saveRefreshHealth(TailOpsRefreshHealth(
                lastAttemptAt: attemptAt,
                lastSuccessAt: Date()
            ))
            reloadWidget()

            // Second phase: node health over SSH and the hourly ping burst run together.
            async let freshHealth = nodeHealth(from: sources)
            var mergedPings = previousPings
            var pingsChanged = false
            if let pingProvider, shouldRefreshPingDiagnostics(now: Date()) {
                let freshPings = await pingSummaries(for: parsed.hosts, using: pingProvider)
                // When every ping failed (often right after wake), try again sooner than hourly.
                lastPingDiagnosticsRefreshDate = freshPings.isEmpty
                    ? Date().addingTimeInterval(pingRetryInterval - pingDiagnosticsMinimumInterval)
                    : Date()
                mergedPings = previousPings.merging(freshPings) { previous, fresh in
                    previous.mergingRecentSamples(from: fresh, maxSamples: maxRetainedPingSamples)
                }
                pingsChanged = true
            }
            let fetchedHealth = await freshHealth
            if pingsChanged || !sources.isEmpty {
                // A node that could not be reached keeps its last reading, marked stale once old.
                let fetchedCollectors = Set(fetchedHealth.map { $0.collector.lowercased() })
                let health = fetchedHealth + previousHealth.filter { !fetchedCollectors.contains($0.collector.lowercased()) }
                do {
                    try publish(Self.snapshot(parsed, applying: mergedPings, health: health, at: Date()))
                    reloadWidget()
                } catch {
                    NSLog("TailOps could not save diagnostics: %@", error.localizedDescription)
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
                let wait = self?.automaticRefreshInterval(default: interval) ?? interval
                do {
                    // Suspending clock: time asleep does not count, so an overdue refresh
                    // does not fire at wake before the network is back. Wake has its own refresh.
                    try await Task.sleep(for: wait, tolerance: .seconds(60), clock: .suspending)
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

    /// Waits a few seconds for the network to settle, and at least until a minute
    /// has passed since the last refresh, so the final event in a burst is honored.
    private func scheduleSystemEventRefresh() {
        systemEventRefreshTask?.cancel()
        let sinceLastRefresh = lastRefreshDate.map { Date().timeIntervalSince($0) } ?? .infinity
        let delay = max(systemEventRefreshDelay, systemEventMinimumInterval - sinceLastRefresh)
        systemEventRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            await refresh()
        }
    }

    private func publish(_ nextSnapshot: TailnetSnapshot) throws {
        snapshot = nextSnapshot
        try tailnetStore.save(nextSnapshot)
    }

    private func reloadWidget() {
        TailOpsWidgetKind.reloadTimelines()
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
        var pending = hosts.filter { $0.role == .peer && $0.status != .offline }[...]
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

    /// Attaches ping history to reachable peers only; offline hosts and this device
    /// carry no ping diagnostics.
    private func automaticRefreshInterval(default interval: Duration) -> Duration {
        healthProvider != nil && !healthSources().isEmpty ? min(interval, healthRefreshInterval) : interval
    }

    /// Reads each configured node's health concurrently; unreachable nodes are skipped.
    private func nodeHealth(from sources: [String]) async -> [TailnetNodeHealth] {
        guard let healthProvider, !sources.isEmpty else { return [] }
        return await withTaskGroup(of: TailnetNodeHealth?.self) { group in
            for source in sources {
                group.addTask { try? await healthProvider.health(from: source) }
            }
            var readings: [TailnetNodeHealth] = []
            for await reading in group {
                if let reading {
                    readings.append(reading)
                }
            }
            return readings
        }
    }

    private static func snapshot(
        _ snapshot: TailnetSnapshot,
        applying pingByHostID: [String: TailnetPingSummary],
        health: [TailnetNodeHealth] = [],
        at date: Date
    ) -> TailnetSnapshot {
        let hosts = snapshot.hosts.map { host in
            var host = host
            if host.role == .peer, host.status != .offline, let ping = pingByHostID[host.id] {
                host = host.withDiagnostics(TailnetHostDiagnostics(ping: ping))
            }
            if let reading = health.first(where: { $0.matches(host) }) {
                host = host.withHealth(reading.checkingStaleness(at: date))
            }
            return host
        }

        return snapshot.withHosts(hosts)
    }
}
