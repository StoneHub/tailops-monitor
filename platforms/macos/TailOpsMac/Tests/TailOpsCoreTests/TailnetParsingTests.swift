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
