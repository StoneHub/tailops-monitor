import Foundation
import XCTest
@testable import TailOpsCore

final class TailnetParsingTests: XCTestCase {
    func testParserKeepsPrimaryAddressAndLastSeen() throws {
        let data = Data(
            """
            {
              "Self": {
                "ID": "self-1",
                "HostName": "monroe-mac",
                "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"],
                "Online": true
              },
              "Peer": {
                "peer-1": {
                  "ID": "peer-1",
                  "HostName": "openclaw",
                  "TailscaleIPs": ["100.64.0.2"],
                  "Online": false,
                  "LastSeen": "2026-05-14T18:30:00Z"
                }
              }
            }
            """.utf8
        )

        let snapshot = try TailnetSnapshotParser().parse(data)

        XCTAssertEqual(snapshot.hosts[0].primaryAddress, "100.64.0.1")
        XCTAssertEqual(snapshot.hosts[1].lastSeen, ISO8601DateFormatter().date(from: "2026-05-14T18:30:00Z"))
    }

    func testParserCleansTailscaleDuplicateDisplaySuffix() throws {
        let data = Data(
            """
            {
              "Peer": {
                "peer-1": {
                  "ID": "peer-1",
                  "HostName": "Sam’s MacBook Pro (2)",
                  "DNSName": "sams-macbook-pro-2.tailnet.ts.net.",
                  "TailscaleIPs": ["100.64.0.113"],
                  "Online": true,
                  "OS": "macOS"
                }
              }
            }
            """.utf8
        )

        let host = try XCTUnwrap(TailnetSnapshotParser().parse(data).hosts.first)

        XCTAssertEqual(host.name, "Sam’s MacBook Pro")
        XCTAssertEqual(host.magicDNSName, "sams-macbook-pro-2.tailnet.ts.net")
        XCTAssertEqual(host.primaryAddress, "100.64.0.113")
    }

    func testParserSortsOnlineHostsFirstThenOfflineByLastSeen() throws {
        let data = Data(
            """
            {
              "Self": { "ID": "self-1", "HostName": "monroe-mac", "Online": true },
              "Peer": {
                "old-peer": { "ID": "old-peer", "HostName": "old-peer", "Online": false, "LastSeen": "2026-05-12T18:30:00Z" },
                "active-peer": { "ID": "active-peer", "HostName": "active-peer", "Online": true },
                "recent-peer": { "ID": "recent-peer", "HostName": "recent-peer", "Online": false, "LastSeen": "2026-05-14T18:30:00Z" }
              }
            }
            """.utf8
        )

        let snapshot = try TailnetSnapshotParser().parse(data)

        XCTAssertEqual(snapshot.hosts.map(\.name), ["monroe-mac", "active-peer", "recent-peer", "old-peer"])
    }

    func testParserReadsBackendHealthAndExitNodeFromHiddenProviderPeer() throws {
        let data = Data(
            """
            {
              "BackendState": "Running",
              "Health": ["  Some peers are advertising routes but --accept-routes is false  ", ""],
              "CurrentTailnet": { "Name": "example.github" },
              "Self": { "ID": "self", "HostName": "this-mac", "Online": true },
              "Peer": {
                "fleet": { "ID": "fleet", "HostName": "fcfdev", "Online": true },
                "provider": {
                  "ID": "provider", "HostName": "us-mia-wg-001", "Online": true, "ExitNode": true,
                  "Tags": ["tag:mullvad-exit-node"],
                  "Location": { "City": "Miami, FL", "Country": "USA" }
                }
              }
            }
            """.utf8
        )

        let snapshot = try TailnetSnapshotParser().parse(data)
        let health = try XCTUnwrap(snapshot.health)

        XCTAssertTrue(health.isRunning)
        XCTAssertNil(health.backendProblem)
        XCTAssertEqual(health.warnings, ["Some peers are advertising routes but --accept-routes is false"])
        XCTAssertEqual(health.tailnetName, "example.github")
        XCTAssertEqual(health.exitNode, TailnetExitNode(name: "us-mia-wg-001", location: "Miami, FL"))
        XCTAssertEqual(snapshot.hosts.map(\.name), ["this-mac", "fcfdev"])
    }

    func testStoppedBackendIsReportedAndMissingStateMeansNoHealth() throws {
        let stopped = try TailnetSnapshotParser().parse(Data(#"{ "BackendState": "Stopped" }"#.utf8))
        let legacy = try TailnetSnapshotParser().parse(Data(#"{ "Peer": {} }"#.utf8))

        XCTAssertEqual(stopped.health?.isRunning, false)
        XCTAssertEqual(stopped.health?.backendProblem, "Tailscale is turned off")
        XCTAssertNil(legacy.health)
    }

    func testParserDerivesPeerConnectionRoutes() throws {
        let data = Data(
            """
            {
              "Self": { "ID": "self", "HostName": "this-mac", "Online": true, "CurAddr": "", "Relay": "iad" },
              "Peer": {
                "a": { "ID": "direct", "HostName": "direct", "Online": true, "Active": true, "CurAddr": "192.0.2.4:41641", "Relay": "mia" },
                "b": { "ID": "derp", "HostName": "derp", "Online": true, "Active": true, "CurAddr": "", "Relay": "mia" },
                "c": { "ID": "relay", "HostName": "relay", "Online": true, "Active": true, "CurAddr": "", "PeerRelay": "198.51.100.7:7777", "Relay": "mia" },
                "d": { "ID": "idle", "HostName": "idle", "Online": true, "Active": false, "CurAddr": "", "Relay": "mia" },
                "e": { "ID": "offline", "HostName": "offline", "Online": false, "Relay": "mia" }
              }
            }
            """.utf8
        )

        let connections = Dictionary(
            uniqueKeysWithValues: try TailnetSnapshotParser().parse(data).hosts.map { ($0.id, $0.connection) }
        )

        XCTAssertEqual(connections["direct"], .direct)
        XCTAssertEqual(connections["derp"], .derp(region: "mia"))
        XCTAssertEqual(connections["relay"], .peerRelay)
        XCTAssertEqual(connections["idle"], .idle)
        XCTAssertEqual(connections["offline"], .some(nil))
        XCTAssertEqual(connections["self"], .some(nil))
        XCTAssertEqual(TailnetConnection.derp(region: "mia").label, "DERP mia")
    }

    func testKeyExpiringWithinAWeekMarksOnlineHostAsWarning() throws {
        let data = Data(
            """
            {
              "Peer": {
                "a": { "ID": "soon", "HostName": "soon", "Online": true, "KeyExpiry": "2026-01-04T00:00:00Z" },
                "b": { "ID": "later", "HostName": "later", "Online": true, "KeyExpiry": "2026-02-01T00:00:00Z" },
                "c": { "ID": "asleep", "HostName": "asleep", "Online": false, "KeyExpiry": "2026-01-02T00:00:00Z" },
                "d": { "ID": "tagged", "HostName": "tagged", "Online": true }
              }
            }
            """.utf8
        )
        let generatedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z"))

        let hosts = try TailnetSnapshotParser().parse(data, generatedAt: generatedAt).hosts
        let status = Dictionary(uniqueKeysWithValues: hosts.map { ($0.id, $0.status) })

        XCTAssertEqual(status, ["soon": .warning, "later": .online, "asleep": .offline, "tagged": .online])
        XCTAssertEqual(hosts.first { $0.id == "soon" }?.keyExpiry, ISO8601DateFormatter().date(from: "2026-01-04T00:00:00Z"))
    }

    func testSnapshotSavedByEarlierBuildsStillDecodes() throws {
        let data = Data(
            """
            {
              "generatedAt": "2026-08-29T14:00:00Z",
              "hosts": [
                {
                  "id": "peer-1", "name": "fcfdev", "role": "peer", "status": "online",
                  "operatingSystem": "linux", "primaryAddress": "100.64.0.2",
                  "magicDNSName": "fcfdev.tailnet.ts.net", "services": []
                }
              ]
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(TailnetSnapshot.self, from: data)

        XCTAssertEqual(snapshot.hosts.map(\.name), ["fcfdev"])
        XCTAssertNil(snapshot.health)
        XCTAssertNil(snapshot.hosts[0].connection)
        XCTAssertNil(snapshot.hosts[0].keyExpiry)
    }

    func testPingParserReadsLatencyAndRouteSamples() throws {
        let output = """
        pong from worker-node (100.64.0.24) via DERP(mia) in 42ms
        pong from worker-node (100.64.0.24) via peer-relay(198.51.100.167:7777:vni:7) in 35.5ms
        pong from worker-node (100.64.0.24) via 192.0.2.64:41642 in 10ms
        """

        let summary = try XCTUnwrap(TailnetPingOutputParser().parse(output))

        XCTAssertEqual(summary.samples.map(\.route), [.derp, .peerRelay, .direct])
        XCTAssertEqual(summary.samples.map(\.latencyMilliseconds), [42, 35.5, 10])
        XCTAssertEqual(summary.latestRoute, .direct)
    }

    func testPingSummaryAveragesAndKeepsRecentSamples() {
        let older = TailnetPingSummary(samples: [
            TailnetPingSample(latencyMilliseconds: 100, route: .derp),
            TailnetPingSample(latencyMilliseconds: 80, route: .peerRelay),
        ], lastUpdated: Date(timeIntervalSince1970: 10))
        let newer = TailnetPingSummary(samples: [
            TailnetPingSample(latencyMilliseconds: 40, route: .direct),
            TailnetPingSample(latencyMilliseconds: 20, route: .direct),
        ], lastUpdated: Date(timeIntervalSince1970: 20))

        let merged = older.mergingRecentSamples(from: newer, maxSamples: 3)

        XCTAssertEqual(merged.samples.map(\.latencyMilliseconds), [80, 40, 20])
        XCTAssertEqual(merged.averageLatencyMilliseconds, 140.0 / 3.0)
        XCTAssertEqual(merged.latestLatencyMilliseconds, 20)
        XCTAssertEqual(merged.latestRoute, .direct)
        XCTAssertEqual(merged.lastUpdated, newer.lastUpdated)
    }

    func testTaildropTargetsParserReadsAvailableAndOfflineTargets() {
        let output = """
        100.64.0.24\tworker-node
        100.64.0.113\tSam’s MacBook Pro (2)
        100.64.0.30\tpixel-6a\toffline; last seen 20h27m0s ago
        """

        XCTAssertEqual(TaildropTargetsParser().parse(output), [
            TaildropTarget(address: "100.64.0.24", name: "worker-node", isAvailable: true),
            TaildropTarget(address: "100.64.0.113", name: "Sam’s MacBook Pro", isAvailable: true),
            TaildropTarget(
                address: "100.64.0.30",
                name: "pixel-6a",
                detail: "offline; last seen 20h27m0s ago",
                isAvailable: false
            ),
        ])
    }
}
