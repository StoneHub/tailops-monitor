import Foundation
import XCTest
@testable import TailOpsCore

final class NodeHealthTests: XCTestCase {
    // Shape written by tailopsd 0.3.0 `--health-output`.
    private let document = Data(
        """
        {
          "schemaVersion": 1,
          "kind": "tailops.host-health",
          "observedAt": "2026-09-26T22:21:08.053Z",
          "collector": { "node": "fcfdev", "source": "tailscale-local-cli" },
          "summary": { "nodeCount": 10, "onlineCount": 3, "offlineCount": 7, "providerNodesExcluded": 536 },
          "host": {
            "hostname": "fcfdev", "os": "Ubuntu 24.04.5 LTS", "uptimeSeconds": 195553,
            "memory": { "totalBytes": 16000, "availableBytes": 4000 },
            "disks": [{ "mount": "/", "totalBytes": 1000, "availableBytes": 550 }],
            "failedUnits": [], "temperatureCelsius": 37.4, "probeErrors": [], "warnings": []
          }
        }
        """.utf8
    )

    func testParsesTheTailopsdHealthDocument() throws {
        let health = try TailnetNodeHealthParser().parse(document)

        XCTAssertEqual(health.collector, "fcfdev")
        XCTAssertEqual(health.uptimeSeconds, 195_553)
        XCTAssertEqual(try XCTUnwrap(health.memoryAvailableRatio), 0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(health.rootDiskUsedRatio), 0.45, accuracy: 0.0001)
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-26T22:21:08Z"))
        XCTAssertEqual(health.observedAt.timeIntervalSince(expected), 0.053, accuracy: 0.001)
        XCTAssertEqual(health.summaryText, "Healthy · 37 °C · disk 45%")
    }

    func testRejectsOtherDocuments() {
        let observation = Data(#"{"schemaVersion":1,"kind":"tailops.fleet-observation","observedAt":"2026-09-26T22:21:08Z"}"#.utf8)
        XCTAssertThrowsError(try TailnetNodeHealthParser().parse(observation)) { error in
            XCTAssertEqual(error as? TailnetNodeHealthError, .notHealthDocument)
        }
    }

    func testWarningsMarkTheHostUntilTheReadingGoesStale() {
        let observedAt = Date(timeIntervalSince1970: 1_000_000)
        let health = TailnetNodeHealth(
            collector: "fcfdev",
            observedAt: observedAt,
            warnings: ["1 failed systemd unit", "disk / is 93% full"]
        )
        let host = TailnetHost(
            id: "n1", name: "fcfdev", role: .peer, status: .online, operatingSystem: "linux",
            primaryAddress: "100.64.0.2", magicDNSName: "fcfdev.tailnet.ts.net", lastSeen: nil, services: []
        )

        let fresh = host.withHealth(health.checkingStaleness(at: observedAt.addingTimeInterval(60)))
        let stale = host.withHealth(health.checkingStaleness(at: observedAt.addingTimeInterval(2 * 60 * 60)))

        XCTAssertTrue(health.matches(host))
        XCTAssertEqual(fresh.status, .warning)
        XCTAssertEqual(fresh.health?.summaryText, "1 failed systemd unit (+1)")
        XCTAssertEqual(stale.status, .online)
        XCTAssertEqual(stale.health?.summaryText, "Health reading is stale")
    }

    func testMatchesByMagicDNSLabel() {
        let health = TailnetNodeHealth(collector: "fcfdev", observedAt: Date())
        let host = TailnetHost(
            id: "n1", name: "FCF Dev Box", role: .peer, status: .online, operatingSystem: "linux",
            primaryAddress: nil, magicDNSName: "fcfdev.tail8797e7.ts.net", lastSeen: nil, services: []
        )
        let other = TailnetHost(
            id: "n2", name: "fcfdev2", role: .peer, status: .online, operatingSystem: "linux",
            primaryAddress: nil, magicDNSName: "fcfdev2.tail8797e7.ts.net", lastSeen: nil, services: []
        )

        XCTAssertTrue(health.matches(host))
        XCTAssertFalse(health.matches(other))
    }
}
