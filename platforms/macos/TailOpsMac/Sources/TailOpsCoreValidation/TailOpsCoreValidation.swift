import Foundation
import TailOpsCore

@main
struct TailOpsCoreValidation {
    static func main() throws {
        try parserMapsSelfAndPeersIntoHostCards()
        actionCatalogBuildsSshAndDashboardLinks()
        actionCatalogUsesConfiguredEmojiActionsBeforeDefaults()
        try actionConfigurationDecodesCustomDashboardLinks()
        actionConfigurationMatchesHostByNameMagicDNSOrAddress()
        actionConfigurationValidationReportsInvalidRows()
        summaryCountsOnlyOnlineHostsAsHealthy()
        print("TailOpsCoreValidation passed")
    }

    private static func parserMapsSelfAndPeersIntoHostCards() throws {
        let json = """
        {
          "Self": {
            "ID": "self-1",
            "HostName": "monroe-mac",
            "DNSName": "monroe-mac.tailnet.ts.net.",
            "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"],
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
        """.data(using: .utf8)!

        let snapshot = try TailnetSnapshotParser().parse(json)

        expect(snapshot.hosts.map(\.name) == ["monroe-mac", "openclaw"], "expected self and peer names")
        expect(snapshot.hosts[0].role == .thisDevice, "expected self host role")
        expect(snapshot.hosts[0].status == .online, "expected self online status")
        expect(snapshot.hosts[0].primaryAddress == "100.64.0.1", "expected primary Tailscale address")
        expect(snapshot.hosts[0].magicDNSName == "monroe-mac.tailnet.ts.net", "expected normalized MagicDNS name")
        expect(snapshot.hosts[1].role == .peer, "expected peer host role")
        expect(snapshot.hosts[1].status == .offline, "expected peer offline status")
        expect(snapshot.hosts[1].lastSeen == ISO8601DateFormatter().date(from: "2026-05-14T18:30:00Z"), "expected parsed last seen date")
    }

    private static func actionCatalogBuildsSshAndDashboardLinks() {
        let host = TailnetHost(
            id: "peer-1",
            name: "openclaw",
            role: .peer,
            status: .online,
            operatingSystem: "linux",
            primaryAddress: "100.64.0.2",
            magicDNSName: "openclaw.tailnet.ts.net",
            lastSeen: nil,
            services: [
                TailnetService(label: "OpenClaw", url: URL(string: "http://openclaw.tailnet.ts.net:8080")!)
            ]
        )

        let actions = HostActionCatalog().actions(for: host)

        expect(actions.map(\.title) == ["SSH", "OpenClaw", "Copy IP"], "expected action titles")
        expect(actions[0].url == URL(string: "ssh://openclaw.tailnet.ts.net"), "expected SSH URL")
        expect(actions[1].url == URL(string: "http://openclaw.tailnet.ts.net:8080"), "expected dashboard URL")
        expect(actions[2].url == nil, "expected copy action to have no URL")
    }

    private static func actionCatalogUsesConfiguredEmojiActionsBeforeDefaults() {
        let host = TailnetHost(
            id: "openclaw",
            name: "openclaw",
            role: .peer,
            status: .online,
            operatingSystem: "linux",
            primaryAddress: "100.64.0.2",
            magicDNSName: "openclaw.tailnet.ts.net",
            lastSeen: nil,
            services: []
        )
        let config = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(
                hostID: "openclaw",
                actions: [
                    TailnetQuickAction(emoji: "🖥", title: "SSH", kind: .ssh, target: "openclaw.tailnet.ts.net"),
                    TailnetQuickAction(emoji: "🧭", title: "Dash", kind: .url, target: "http://openclaw.tailnet.ts.net:8080"),
                    TailnetQuickAction(emoji: "📋", title: "IP", kind: .copy, target: "100.64.0.2")
                ]
            )
        ])

        let actions = HostActionCatalog(configuration: config).actions(for: host)

        expect(actions.map(\.emoji) == ["🖥", "🧭", "📋"], "expected configured emoji actions")
        expect(actions.map(\.title) == ["SSH", "Dash", "IP"], "expected configured action titles")
        expect(actions[0].url == URL(string: "ssh://openclaw.tailnet.ts.net"), "expected configured SSH URL")
        expect(actions[1].url == URL(string: "http://openclaw.tailnet.ts.net:8080"), "expected configured dashboard URL")
        expect(actions[2].kind == .copyAddress, "expected configured copy action")
        expect(actions[2].value == "100.64.0.2", "expected configured copy value")
    }

    private static func actionConfigurationDecodesCustomDashboardLinks() throws {
        let json = """
        {
          "hostActions": [
            {
              "hostID": "openclaw",
              "actions": [
                { "emoji": "🧭", "title": "Dash", "kind": "url", "target": "http://openclaw.tailnet.ts.net:8080" },
                { "emoji": "🖥", "title": "SSH", "kind": "ssh", "target": "openclaw.tailnet.ts.net" }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(TailnetActionConfiguration.self, from: json)

        expect(config.hostActions.count == 1, "expected one configured host")
        expect(config.hostActions[0].hostID == "openclaw", "expected host identifier")
        expect(config.hostActions[0].actions.map(\.title) == ["Dash", "SSH"], "expected custom action titles")
        expect(config.hostActions[0].actions[0].kind == .url, "expected dashboard URL action")
        expect(config.hostActions[0].actions[0].target == "http://openclaw.tailnet.ts.net:8080", "expected dashboard URL target")
    }

    private static func actionConfigurationMatchesHostByNameMagicDNSOrAddress() {
        let host = TailnetHost(
            id: "peer-1",
            name: "openclaw",
            role: .peer,
            status: .online,
            operatingSystem: "linux",
            primaryAddress: "100.64.0.2",
            magicDNSName: "openclaw.tailnet.ts.net",
            lastSeen: nil,
            services: []
        )
        let config = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(
                hostID: "openclaw.tailnet.ts.net",
                actions: [
                    TailnetQuickAction(emoji: "🧭", title: "Dash", kind: .url, target: "http://openclaw.tailnet.ts.net:8080")
                ]
            )
        ])

        expect(config.actions(for: host).map(\.title) == ["Dash"], "expected MagicDNS host match")
    }

    private static func actionConfigurationValidationReportsInvalidRows() {
        let config = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(
                hostID: "",
                actions: [
                    TailnetQuickAction(emoji: "", title: "Dash", kind: .url, target: "not-a-url"),
                    TailnetQuickAction(emoji: "🖥", title: "SSH", kind: .ssh, target: "ssh://openclaw.tailnet.ts.net"),
                    TailnetQuickAction(emoji: "📋", title: "", kind: .copy, target: "")
                ]
            )
        ])

        let issues = config.validationIssues()

        expect(issues.contains(.emptyHostID(hostIndex: 0)), "expected empty host issue")
        expect(issues.contains(.emptyEmoji(hostIndex: 0, actionIndex: 0)), "expected empty emoji issue")
        expect(issues.contains(.invalidURL(hostIndex: 0, actionIndex: 0)), "expected invalid URL issue")
        expect(issues.contains(.sshTargetContainsScheme(hostIndex: 0, actionIndex: 1)), "expected SSH scheme issue")
        expect(issues.contains(.emptyTitle(hostIndex: 0, actionIndex: 2)), "expected empty title issue")
        expect(issues.contains(.emptyTarget(hostIndex: 0, actionIndex: 2)), "expected empty target issue")
    }

    private static func summaryCountsOnlyOnlineHostsAsHealthy() {
        let summary = TailnetSummary(
            hosts: [
                fixture(status: .online),
                fixture(id: "warning", status: .warning),
                fixture(id: "offline", status: .offline)
            ]
        )

        expect(summary.onlineCount == 1, "expected one online host")
        expect(summary.warningCount == 1, "expected one warning host")
        expect(summary.offlineCount == 1, "expected one offline host")
        expect(summary.trafficLight == .warning, "expected warning traffic light to take precedence")
    }

    private static func fixture(id: String = "host", status: TailnetHost.Status) -> TailnetHost {
        TailnetHost(
            id: id,
            name: id,
            role: .peer,
            status: status,
            operatingSystem: nil,
            primaryAddress: "100.64.0.10",
            magicDNSName: nil,
            lastSeen: nil,
            services: []
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
