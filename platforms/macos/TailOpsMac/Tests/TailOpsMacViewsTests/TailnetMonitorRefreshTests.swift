import Foundation
import XCTest
@testable import TailOpsCore
@testable import TailOpsMacViews
@testable import TailOpsShared

@MainActor
final class TailnetMonitorRefreshTests: XCTestCase {
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
