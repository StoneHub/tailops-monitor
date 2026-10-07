import Foundation
import XCTest
@testable import TailOpsCore
@testable import TailOpsMacViews
@testable import TailOpsShared

@MainActor
final class TailnetMonitorRefreshTests: XCTestCase {
    func testRequestDuringDiagnosticsRemainsPendingUntilNextStatusAttempt() async throws {
        let store = RecordingTailnetStore()
        let requestStore = InMemoryTailOpsStore()
        let pingStarted = expectation(description: "Diagnostics started")
        let pingProvider = SuspendedPingProvider(started: pingStarted)
        let monitor = TailnetMonitor(
            statusProvider: FakeStatusProvider(peerCount: 1),
            pingProvider: pingProvider,
            tailnetStore: store,
            requestStore: requestStore
        )
        let refreshTask = Task { await monitor.refresh() }
        let result = await XCTWaiter.fulfillment(of: [pingStarted], timeout: 2)
        XCTAssertEqual(result, .completed)
        let successAt = try XCTUnwrap(store.health?.lastSuccessAt)
        let request = TailOpsRefreshRequest(requestedAt: successAt.addingTimeInterval(1))
        try requestStore.saveRefreshRequest(request)

        let queued = await monitor.refreshIfRequested()

        XCTAssertTrue(queued)
        XCTAssertEqual(try requestStore.loadRefreshRequest(), request)
        let pendingHealth = try XCTUnwrap(store.health).including(requestStore.loadRefreshRequest())
        XCTAssertTrue(pendingHealth.isRefreshInProgress(at: request.requestedAt))
        XCTAssertTrue(pendingHealth.hasTimedOut(at: request.requestedAt.addingTimeInterval(120)))

        await pingProvider.resume()
        await refreshTask.value
        XCTAssertNil(try requestStore.loadRefreshRequest())
        XCTAssertEqual(store.savedSnapshots.count, 3)
        XCTAssertFalse(try XCTUnwrap(store.health).isRefreshInProgress)
    }

    func testRefreshSignalConsumesQueuedRequestInRunningHost() async throws {
        let store = RecordingTailnetStore()
        let requestStore = InMemoryTailOpsStore(refreshRequest: TailOpsRefreshRequest())
        let monitor = TailnetMonitor(
            statusProvider: FakeStatusProvider(peerCount: 1),
            tailnetStore: store,
            requestStore: requestStore
        )
        let refreshed = expectation(description: "Fresh status saved after URL handoff signal")
        store.didSave = { refreshed.fulfill() }

        NotificationCenter.default.post(
            name: Notification.Name(TailOpsRefreshSignal.notificationName),
            object: nil
        )
        let result = await XCTWaiter.fulfillment(of: [refreshed], timeout: 2)

        XCTAssertEqual(result, .completed)
        XCTAssertNil(try requestStore.loadRefreshRequest())
        XCTAssertEqual(monitor.snapshot.hosts.count, 2)
        XCTAssertNotNil(store.health?.lastSuccessAt)
    }

    func testActivationWithoutQueuedRequestDoesNotRefresh() async throws {
        let store = RecordingTailnetStore()
        let monitor = makeMonitor(peerCount: 1, pingProvider: FakePingProvider(), store: store)

        let didRefresh = await monitor.refreshIfRequested()

        XCTAssertFalse(didRefresh)
        XCTAssertTrue(store.savedSnapshots.isEmpty)
    }

    func testFailedStatusKeepsSnapshotAgeAndPublishesError() async throws {
        let store = RecordingTailnetStore()
        let snapshot = TailnetSnapshot(hosts: [], generatedAt: Date().addingTimeInterval(-60))
        try store.save(snapshot)
        let monitor = TailnetMonitor(
            statusProvider: FailedStatusProvider(),
            tailnetStore: store,
            requestStore: InMemoryTailOpsStore(refreshRequest: TailOpsRefreshRequest())
        )

        await monitor.refreshIfRequested()

        XCTAssertEqual(store.savedSnapshots, [snapshot])
        XCTAssertEqual(monitor.snapshot.generatedAt, snapshot.generatedAt)
        XCTAssertEqual(store.health?.lastError, "Tailscale unavailable")
        XCTAssertTrue(try XCTUnwrap(store.health).hasFailedSinceLastSuccess)
        XCTAssertFalse(try XCTUnwrap(store.health).hasTimedOut(at: Date().addingTimeInterval(120)))
    }

    func testStatusIsPublishedBeforePingDiagnostics() async throws {
        let store = RecordingTailnetStore()
        let monitor = makeMonitor(peerCount: 2, pingProvider: FakePingProvider(), store: store)

        await monitor.refresh()

        XCTAssertEqual(store.savedSnapshots.count, 2)
        XCTAssertTrue(store.savedSnapshots[0].hosts.allSatisfy { $0.diagnostics == nil })
        XCTAssertEqual(store.savedSnapshots[1].hosts.filter { $0.diagnostics?.ping != nil }.count, 2)
        XCTAssertNotNil(store.health?.lastSuccessAt)
    }

    func testPingsRunConcurrentlyWithinTheLimit() async throws {
        let pingProvider = FakePingProvider(delay: .milliseconds(50))
        let monitor = makeMonitor(peerCount: 9, pingProvider: pingProvider, store: RecordingTailnetStore())

        await monitor.refresh()

        let maximum = await pingProvider.maximumInFlight
        let pinged = await pingProvider.pingedHostIDs
        XCTAssertEqual(maximum, 4)
        XCTAssertEqual(Set(pinged), Set((1...9).map { "peer-\($0)" }))
    }

    func testFailedPingKeepsEarlierSamples() async throws {
        let earlier = TailnetPingSummary(
            samples: [TailnetPingSample(latencyMilliseconds: 12, route: .direct)],
            lastUpdated: Date().addingTimeInterval(-2 * 60 * 60)
        )
        let initialSnapshot = TailnetSnapshot(hosts: [
            TailnetHost(
                id: "peer-1", name: "peer-1", role: .peer, status: .online,
                operatingSystem: "linux", primaryAddress: "100.64.0.11", magicDNSName: nil,
                lastSeen: nil, services: [],
                diagnostics: TailnetHostDiagnostics(ping: earlier)
            ),
        ])
        let store = RecordingTailnetStore()
        let monitor = makeMonitor(
            peerCount: 1,
            pingProvider: FakePingProvider(failingHostIDs: ["peer-1"]),
            store: store,
            initialSnapshot: initialSnapshot
        )

        await monitor.refresh()

        let saved = try XCTUnwrap(store.savedSnapshots.last?.hosts.first { $0.id == "peer-1" })
        XCTAssertEqual(saved.diagnostics?.ping, earlier)
    }

    func testPeersWithExpiringKeysAreStillPinged() async throws {
        let store = RecordingTailnetStore()
        let monitor = TailnetMonitor(
            statusProvider: ExpiringKeyStatusProvider(),
            pingProvider: FakePingProvider(),
            tailnetStore: store,
            requestStore: InMemoryTailOpsStore()
        )

        await monitor.refresh()

        let peer = try XCTUnwrap(store.savedSnapshots.last?.hosts.first { $0.id == "peer-1" })
        XCTAssertEqual(peer.status, .warning)
        XCTAssertNotNil(peer.diagnostics?.ping)
    }

    func testNodeHealthIsAttachedAndKeptStaleWhenUnreachable() async throws {
        let store = RecordingTailnetStore()
        let provider = FakeHealthProvider()
        await provider.set(TailnetNodeHealth(collector: "peer-1", observedAt: Date(), warnings: ["1 failed systemd unit"]))
        let monitor = TailnetMonitor(
            statusProvider: FakeStatusProvider(peerCount: 2),
            healthProvider: provider,
            healthSources: { ["peer-1"] },
            tailnetStore: store,
            requestStore: InMemoryTailOpsStore()
        )

        await monitor.refresh()

        let first = try XCTUnwrap(store.savedSnapshots.last?.hosts.first { $0.id == "peer-1" })
        XCTAssertEqual(first.status, .warning)
        XCTAssertEqual(first.health?.warnings, ["1 failed systemd unit"])
        XCTAssertNil(store.savedSnapshots.last?.hosts.first { $0.id == "peer-2" }?.health)

        // The node stops answering: its last reading stays attached.
        await provider.set(nil)
        await monitor.refresh()

        let second = try XCTUnwrap(store.savedSnapshots.last?.hosts.first { $0.id == "peer-1" })
        XCTAssertEqual(second.health?.collector, "peer-1")
    }

    private func makeMonitor(
        peerCount: Int,
        pingProvider: FakePingProvider,
        store: RecordingTailnetStore,
        initialSnapshot: TailnetSnapshot? = nil
    ) -> TailnetMonitor {
        TailnetMonitor(
            statusProvider: FakeStatusProvider(peerCount: peerCount),
            pingProvider: pingProvider,
            tailnetStore: store,
            requestStore: InMemoryTailOpsStore(),
            initialSnapshot: initialSnapshot
        )
    }
}

private struct FakeStatusProvider: TailscaleStatusProviding {
    let peerCount: Int

    func statusJSON() async throws -> Data {
        let peers = (1...peerCount).map { index in
            """
            "peer-\(index)": { "ID": "peer-\(index)", "HostName": "peer-\(index)", "TailscaleIPs": ["100.64.0.\(10 + index)"], "Online": true }
            """
        }
        return Data(
            """
            {
              "Self": { "ID": "self", "HostName": "this-mac", "TailscaleIPs": ["100.64.0.1"], "Online": true },
              "Peer": { \(peers.joined(separator: ",")) }
            }
            """.utf8
        )
    }
}

private struct FailedStatusProvider: TailscaleStatusProviding {
    func statusJSON() async throws -> Data {
        throw TailscaleStatusError.commandFailed("Tailscale unavailable")
    }
}

private struct ExpiringKeyStatusProvider: TailscaleStatusProviding {
    func statusJSON() async throws -> Data {
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(2 * 24 * 60 * 60))
        return Data(
            """
            {
              "Peer": {
                "peer-1": { "ID": "peer-1", "HostName": "peer-1", "TailscaleIPs": ["100.64.0.11"], "Online": true, "KeyExpiry": "\(expiry)" }
              }
            }
            """.utf8
        )
    }
}

private actor FakeHealthProvider: FleetHealthProviding {
    private var reading: TailnetNodeHealth?

    func set(_ reading: TailnetNodeHealth?) {
        self.reading = reading
    }

    func health(from source: String) async throws -> TailnetNodeHealth {
        guard let reading else { throw TailscaleStatusError.commandFailed("unreachable") }
        return reading
    }
}

private actor SuspendedPingProvider: TailscalePingProviding {
    private let started: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?

    init(started: XCTestExpectation) { self.started = started }

    func pingSummary(for host: TailnetHost) async throws -> TailnetPingSummary? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
        return TailnetPingSummary(samples: [TailnetPingSample(latencyMilliseconds: 20, route: .direct)])
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor FakePingProvider: TailscalePingProviding {
    private let delay: Duration
    private let failingHostIDs: Set<String>
    private var inFlight = 0
    private(set) var maximumInFlight = 0
    private(set) var pingedHostIDs: [String] = []

    init(delay: Duration = .zero, failingHostIDs: Set<String> = []) {
        self.delay = delay
        self.failingHostIDs = failingHostIDs
    }

    func pingSummary(for host: TailnetHost) async throws -> TailnetPingSummary? {
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        pingedHostIDs.append(host.id)
        defer { inFlight -= 1 }
        try await Task.sleep(for: delay)
        if failingHostIDs.contains(host.id) {
            throw TailscaleStatusError.commandFailed("ping failed")
        }
        return TailnetPingSummary(samples: [TailnetPingSample(latencyMilliseconds: 20, route: .direct)])
    }
}

private final class RecordingTailnetStore: TailnetStateStoring, @unchecked Sendable {
    private(set) var savedSnapshots: [TailnetSnapshot] = []
    private(set) var health: TailOpsRefreshHealth?
    var didSave: (() -> Void)?

    func load() throws -> TailnetSnapshot? { savedSnapshots.last }
    func save(_ snapshot: TailnetSnapshot) throws {
        savedSnapshots.append(snapshot)
        didSave?()
    }
    func loadRefreshHealth() throws -> TailOpsRefreshHealth? { health }
    func saveRefreshHealth(_ health: TailOpsRefreshHealth) throws { self.health = health }
}
