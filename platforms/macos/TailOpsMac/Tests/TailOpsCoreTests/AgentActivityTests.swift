import Foundation
import XCTest
@testable import TailOpsCore

final class AgentActivityTests: XCTestCase {
    // Shape written by the Fleet agent observer's drainer (stack/agent-observer/drainer.py).
    private let document = Data(
        """
        {
          "schema": "fleet.agent-state/1",
          "host": "fcfdev",
          "generatedAt": "2026-11-14T20:02:20+00:00",
          "summary": { "working": 2, "waiting": 1, "idle": 3, "stale": 0, "attention": 1 },
          "agents": [
            { "id": "s1", "harness": "claude-code", "project": "fleet", "kind": "main", "status": "waiting",
              "attention": { "kind": "permission", "since": "2026-11-14T20:01:00+00:00" }, "model": "claude-test" },
            { "id": "oc1", "harness": "openclaw", "project": "openclaw", "kind": "main", "status": "working" },
            { "id": "oc2", "harness": "openclaw", "project": "openclaw", "kind": "main", "status": "working" },
            { "id": "c1", "harness": "codex", "project": "fleet", "kind": "main", "status": "idle" }
          ],
          "usageToday": {}
        }
        """.utf8
    )

    private let readAt = ISO8601DateFormatter().date(from: "2026-11-14T20:03:00Z")!

    func testParsesTheObserverStateDocument() throws {
        let activity = try TailnetAgentActivityParser().parse(document, source: "fcfdev", readAt: readAt)

        XCTAssertEqual(activity.collector, "fcfdev")
        XCTAssertEqual(activity.generatedAt, ISO8601DateFormatter().date(from: "2026-11-14T20:02:20Z"))
        XCTAssertEqual([activity.working, activity.waiting, activity.idle], [2, 1, 3])
        XCTAssertEqual(activity.activeHarnesses, ["claude-code", "openclaw"])
        XCTAssertEqual(activity.summaryText, "2 working · 1 needs you")
        XCTAssertEqual(activity.sourceKey, "fcfdev")
    }

    func testParsesTheCountsOnlySummary() throws {
        let summary = Data(
            #"{"schema":"fleet.agent-summary/1","host":"fcfdev","generatedAt":"2026-11-14T20:02:20+00:00","summary":{"working":1,"waiting":0,"idle":2,"stale":0},"activeHarnesses":["openclaw"]}"#.utf8
        )
        let activity = try TailnetAgentActivityParser().parse(summary, source: "fcfdev", readAt: readAt)

        XCTAssertEqual([activity.working, activity.waiting, activity.idle], [1, 0, 2])
        XCTAssertEqual(activity.activeHarnesses, ["openclaw"])
        XCTAssertEqual(activity.summaryText, "Claw · 1 working")
    }

    func testSummaryURLUsesTheHostsMagicDNSName() {
        let host = TailnetHost(
            id: "n1", name: "fcfdev", role: .peer, status: .online, operatingSystem: "linux",
            primaryAddress: "100.64.0.2", magicDNSName: "fcfdev.tail8797e7.ts.net", lastSeen: nil, services: []
        )
        let bare = host.withAgents(nil)
        XCTAssertEqual(
            TailnetAgentActivity.summaryURL(for: bare)?.absoluteString,
            "https://fcfdev.tail8797e7.ts.net/fleet/agent-summary.json"
        )
        let noDNS = TailnetHost(
            id: "n2", name: "x", role: .peer, status: .online, operatingSystem: nil,
            primaryAddress: "100.64.0.3", magicDNSName: nil, lastSeen: nil, services: []
        )
        XCTAssertNil(TailnetAgentActivity.summaryURL(for: noDNS))
    }

    func testRejectsOtherDocuments() {
        let health = Data(#"{"schemaVersion":1,"kind":"tailops.host-health","observedAt":"2026-09-26T22:21:08Z"}"#.utf8)
        XCTAssertThrowsError(try TailnetAgentActivityParser().parse(health, source: "fcfdev", readAt: readAt))
        let other = Data(#"{"schema":"fleet.agent-event/1","generatedAt":"2026-11-14T20:02:20+00:00","summary":{}}"#.utf8)
        XCTAssertThrowsError(try TailnetAgentActivityParser().parse(other, source: nil, readAt: readAt)) { error in
            XCTAssertEqual(error as? TailnetAgentActivityError, .notAgentState)
        }
    }

    func testSummaryText() {
        func text(_ working: Int, _ waiting: Int, _ harnesses: [String], generatedAgo: TimeInterval = 60) -> String {
            TailnetAgentActivity(
                source: nil, collector: "mac", generatedAt: readAt.addingTimeInterval(-generatedAgo), readAt: readAt,
                working: working, waiting: waiting, idle: 0, activeHarnesses: harnesses
            ).summaryText
        }
        XCTAssertEqual(text(1, 0, ["openclaw"]), "Claw · 1 working")
        XCTAssertEqual(text(0, 2, ["claude-code"]), "Claude · 2 need you")
        XCTAssertEqual(text(0, 0, []), "No agents working")
        XCTAssertEqual(text(3, 0, ["claude-code", "codex"]), "3 working")
        XCTAssertEqual(text(1, 0, ["codex"], generatedAgo: 20 * 60), "Agent observer quiet")
    }

    func testReadingDropsOffAfterTheDisplayInterval() {
        let activity = TailnetAgentActivity(
            source: "fcfdev", collector: "fcfdev", generatedAt: readAt, readAt: readAt, working: 1, waiting: 0, idle: 0
        )
        XCTAssertTrue(activity.isShown(at: readAt.addingTimeInterval(29 * 60)))
        XCTAssertFalse(activity.isShown(at: readAt.addingTimeInterval(30 * 60)))
        XCTAssertEqual(activity.hidesAt, readAt.addingTimeInterval(TailnetAgentActivity.displayInterval))
    }

    func testMatchesThisMacLocallyAndOtherHostsByAliasOrName() {
        let mac = TailnetHost(
            id: "self", name: "monroes-macbook-pro-1", role: .thisDevice, status: .online, operatingSystem: "macOS",
            primaryAddress: nil, magicDNSName: "monroes-macbook-pro-1.tail.ts.net", lastSeen: nil, services: []
        )
        let fcfdev = TailnetHost(
            id: "n1", name: "fcfdev", role: .peer, status: .online, operatingSystem: "linux",
            primaryAddress: nil, magicDNSName: "fcfdev.tail.ts.net", lastSeen: nil, services: []
        )
        let local = TailnetAgentActivity(
            source: nil, collector: "Monroes-MacBook-Pro", generatedAt: readAt, readAt: readAt, working: 0, waiting: 0, idle: 0
        )
        let remote = TailnetAgentActivity(
            source: "fcfdev", collector: "fcfdev", generatedAt: readAt, readAt: readAt, working: 0, waiting: 0, idle: 0
        )
        XCTAssertTrue(local.matches(mac))
        XCTAssertFalse(local.matches(fcfdev))
        XCTAssertTrue(remote.matches(fcfdev))
        XCTAssertFalse(remote.matches(mac))
    }

    func testSnapshotsWithoutAgentsStillDecodeAndAgentsRoundTrip() throws {
        let host = TailnetHost(
            id: "n1", name: "fcfdev", role: .peer, status: .online, operatingSystem: "linux",
            primaryAddress: "100.64.0.2", magicDNSName: nil, lastSeen: nil, services: []
        )
        let activity = TailnetAgentActivity(
            source: "fcfdev", collector: "fcfdev", generatedAt: readAt, readAt: readAt,
            working: 1, waiting: 0, idle: 0, activeHarnesses: ["openclaw"]
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let withAgents = host.withAgents(activity).withHealth(nil)
        XCTAssertEqual(try decoder.decode(TailnetHost.self, from: encoder.encode(withAgents)).agents, activity)
        XCTAssertNil(try decoder.decode(TailnetHost.self, from: encoder.encode(host)).agents)
    }
}
