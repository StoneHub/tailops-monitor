import Foundation
import XCTest
@testable import TailOpsCore
@testable import TailOpsShared

final class TailOpsCoreTests: XCTestCase {
    func testParserMapsSelfAndPeerAndNormalizesMagicDNS() throws {
        let data = try XCTUnwrap(
            """
            {
              "Self": {
                "ID": "self-1",
                "HostName": "monroe-mac",
                "DNSName": "monroe-mac.tailnet.ts.net.",
                "TailscaleIPs": ["100.64.0.1"],
                "Online": true,
                "OS": "macOS"
              },
              "Peer": {
                "peer-1": {
                  "ID": "peer-1",
                  "HostName": "openclaw",
                  "DNSName": "openclaw.tailnet.ts.net.",
                  "TailscaleIPs": ["100.64.0.2"],
                  "Online": false,
                  "LastSeen": "2026-05-14T18:30:00Z",
                  "OS": "linux"
                }
              }
            }
            """.data(using: .utf8)
        )

        let snapshot = try TailnetSnapshotParser().parse(
            data,
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(snapshot.hosts.map(\.name), ["monroe-mac", "openclaw"])
        XCTAssertEqual(snapshot.hosts[0].role, .thisDevice)
        XCTAssertEqual(snapshot.hosts[0].status, .online)
        XCTAssertEqual(snapshot.hosts[0].magicDNSName, "monroe-mac.tailnet.ts.net")
        XCTAssertEqual(snapshot.hosts[1].role, .peer)
        XCTAssertEqual(snapshot.hosts[1].status, .offline)
        XCTAssertEqual(snapshot.generatedAt, Date(timeIntervalSince1970: 1_000))
    }

    func testWidgetLayoutPrioritizesReachablePeerAndCountsHiddenOfflineHosts() {
        let hosts = [
            host(id: "this-device", role: .thisDevice, status: .online),
            host(id: "offline-a", status: .offline),
            host(id: "warning-peer", status: .warning),
            host(id: "online-peer", status: .online),
            host(id: "offline-b", status: .offline),
        ]

        let layout = TailnetWidgetHostLayout(hosts: hosts, limit: 2)

        XCTAssertEqual(layout.visibleHosts.map(\.id), ["online-peer", "warning-peer"])
        XCTAssertEqual(layout.hiddenOfflineCount, 2)
    }

    func testRefreshHealthDistinguishesSuccessProgressFailureAndTimeout() {
        let successful = TailOpsRefreshHealth(
            lastAttemptAt: Date(timeIntervalSince1970: 100),
            lastSuccessAt: Date(timeIntervalSince1970: 100)
        )
        let refreshing = TailOpsRefreshHealth(
            lastAttemptAt: Date(timeIntervalSince1970: 200),
            lastSuccessAt: Date(timeIntervalSince1970: 100)
        )
        let failed = TailOpsRefreshHealth(
            lastAttemptAt: Date(timeIntervalSince1970: 200),
            lastSuccessAt: Date(timeIntervalSince1970: 100),
            lastError: "Tailscale unavailable"
        )

        XCTAssertFalse(successful.isRefreshInProgress)
        XCTAssertTrue(refreshing.isRefreshInProgress)
        XCTAssertTrue(refreshing.isRefreshInProgress(at: Date(timeIntervalSince1970: 250)))
        XCTAssertFalse(refreshing.isRefreshInProgress(at: Date(timeIntervalSince1970: 400)))
        XCTAssertTrue(failed.hasFailedSinceLastSuccess)
        XCTAssertFalse(failed.isRefreshInProgress)
    }

    func testActionValidationRejectsMalformedURLAndSSHScheme() {
        let configuration = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(
                hostID: "peer",
                actions: [
                    TailnetQuickAction(emoji: "W", title: "Web", kind: .url, target: "peer.local"),
                    TailnetQuickAction(emoji: "S", title: "SSH", kind: .ssh, target: "ssh://peer.local"),
                ]
            ),
        ])

        XCTAssertEqual(
            configuration.validationIssues(),
            [
                .invalidURL(hostIndex: 0, actionIndex: 0),
                .sshTargetContainsScheme(hostIndex: 0, actionIndex: 1),
            ]
        )
    }

    func testRefreshRequestAndHealthRoundTripAndRequestClears() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "TailOpsCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = SharedSnapshotStore(baseURLs: [rootURL])
        let request = TailOpsRefreshRequest(requestedAt: Date(timeIntervalSince1970: 100))
        let health = TailOpsRefreshHealth(
            lastAttemptAt: Date(timeIntervalSince1970: 300),
            lastSuccessAt: Date(timeIntervalSince1970: 200),
            lastError: "Tailscale unavailable"
        )

        try store.saveRefreshRequest(request)
        try store.saveRefreshHealth(health)

        XCTAssertEqual(try store.loadRefreshRequest(), request)
        XCTAssertEqual(try store.loadRefreshHealth(), health)

        try store.clearRefreshRequest()
        XCTAssertNil(try store.loadRefreshRequest())
    }

    func testSharedSnapshotStoreFallsBackToNextReadableLocation() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "TailOpsCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let primaryURL = rootURL.appending(path: "primary", directoryHint: .isDirectory)
        let fallbackURL = rootURL.appending(path: "fallback", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fallbackStore = SharedSnapshotStore(baseURLs: [fallbackURL])
        let snapshot = TailnetSnapshot(
            hosts: [host(id: "fallback-peer", status: .online)],
            generatedAt: Date(timeIntervalSince1970: 500)
        )
        try fallbackStore.save(snapshot)

        let loaded = try SharedSnapshotStore(baseURLs: [primaryURL, fallbackURL]).load()

        XCTAssertEqual(loaded, snapshot)
    }

    func testWormholeSecretMigrationPreservesKeychainAndScrubsEveryStorageRoot() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "TailOpsSecretMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let primaryURL = rootURL.appending(path: "primary", directoryHint: .isDirectory)
        let fallbackURL = rootURL.appending(path: "fallback", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: primaryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fallbackURL, withIntermediateDirectories: true)

        let primaryJSON = """
        {"contacts":[{"id":"ben","displayName":"Ben","pairingID":"pair","sharedSecret":"stale-primary","createdAt":"2026-07-12T00:00:00Z"}],"inboxPath":"~/Desktop/TailOps Inbox","pendingSignalPort":39117}
        """
        let fallbackJSON = """
        {"contacts":[{"id":"ben","displayName":"Ben","pairingID":"pair","sharedSecret":"stale-fallback","createdAt":"2026-07-12T00:00:00Z"},{"id":"monroe","displayName":"Monroe","pairingID":"pair","sharedSecret":"migrate-me","createdAt":"2026-07-12T00:00:00Z"}],"inboxPath":"~/Desktop/TailOps Inbox","pendingSignalPort":39117}
        """
        let primaryConfigURL = primaryURL.appending(path: "tailops-wormhole.json")
        let fallbackConfigURL = fallbackURL.appending(path: "tailops-wormhole.json")
        try Data(primaryJSON.utf8).write(to: primaryConfigURL)
        try Data(fallbackJSON.utf8).write(to: fallbackConfigURL)

        let secretStore = InMemoryWormholeSecretStore(secrets: ["ben": "keychain-existing"])
        let store = SharedSnapshotStore(baseURLs: [primaryURL, fallbackURL])
        let configuration = try store.loadWormholeConfigurationMigratingSecrets(to: secretStore)

        XCTAssertEqual(configuration?.contacts.first?.id, "ben")
        XCTAssertEqual(try secretStore.secret(for: "ben"), "keychain-existing")
        XCTAssertEqual(try secretStore.secret(for: "monroe"), "migrate-me")
        XCTAssertFalse(try String(contentsOf: primaryConfigURL, encoding: .utf8).contains("sharedSecret"))
        XCTAssertFalse(try String(contentsOf: fallbackConfigURL, encoding: .utf8).contains("sharedSecret"))
    }

    private func host(
        id: String,
        role: TailnetHost.Role = .peer,
        status: TailnetHost.Status
    ) -> TailnetHost {
        TailnetHost(
            id: id,
            name: id,
            role: role,
            status: status,
            operatingSystem: nil,
            primaryAddress: "100.64.0.10",
            magicDNSName: "\(id).tailnet.ts.net",
            lastSeen: nil,
            services: []
        )
    }
}

private final class InMemoryWormholeSecretStore: TailOpsWormholeSecretStoring, @unchecked Sendable {
    private var secrets: [String: String]

    init(secrets: [String: String] = [:]) {
        self.secrets = secrets
    }

    func secret(for contactID: String) throws -> String? {
        secrets[contactID]
    }

    func save(secret: String, for contactID: String) throws {
        secrets[contactID] = secret
    }
}
