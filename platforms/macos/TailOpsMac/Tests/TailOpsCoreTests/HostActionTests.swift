import Foundation
import XCTest
@testable import TailOpsCore

final class HostActionTests: XCTestCase {
    func testCatalogBuildsSSHDashboardAndCopyDefaults() {
        let host = host(
            id: "peer-1",
            name: "openclaw",
            services: [TailnetService(label: "OpenClaw", url: URL(string: "http://openclaw.tailnet.ts.net:8080")!)]
        )

        let actions = HostActionCatalog().actions(for: host)

        XCTAssertEqual(actions.map(\.title), ["SSH", "OpenClaw", "Copy IP"])
        XCTAssertEqual(actions[0].url, URL(string: "ssh://openclaw.tailnet.ts.net"))
        XCTAssertEqual(actions[1].url, URL(string: "http://openclaw.tailnet.ts.net:8080"))
        XCTAssertNil(actions[2].url)
    }

    func testConfiguredActionsReplaceMatchingDefaults() {
        let configuration = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(hostID: "openclaw", actions: [
                TailnetQuickAction(emoji: "🖥", title: "SSH", kind: .ssh, target: "openclaw.tailnet.ts.net"),
                TailnetQuickAction(emoji: "🧭", title: "Dash", kind: .url, target: "http://openclaw.tailnet.ts.net:8080"),
                TailnetQuickAction(emoji: "📋", title: "IP", kind: .copy, target: "100.64.0.2"),
            ]),
        ])

        let actions = HostActionCatalog(configuration: configuration).actions(for: host(id: "openclaw", name: "openclaw"))

        XCTAssertEqual(actions.map(\.emoji), ["🖥", "🧭", "📋"])
        XCTAssertEqual(actions.map(\.title), ["SSH", "Dash", "IP"])
        XCTAssertEqual(actions[0].url, URL(string: "ssh://openclaw.tailnet.ts.net"))
        XCTAssertEqual(actions[1].url, URL(string: "http://openclaw.tailnet.ts.net:8080"))
        XCTAssertEqual(actions[2].kind, .copyAddress)
        XCTAssertEqual(actions[2].value, "100.64.0.2")
    }

    func testConfiguredActionKeepsUnrelatedDefaults() {
        let configuration = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(hostID: "worker-node", actions: [
                TailnetQuickAction(emoji: "🌐", title: "Panel", kind: .url, target: "http://worker-node.example.test:8080"),
            ]),
        ])
        let host = host(id: "worker-node", name: "worker-node", magicDNSName: "worker-node.example.test")

        let actions = HostActionCatalog(configuration: configuration).actions(for: host)

        XCTAssertEqual(actions.map(\.title), ["Panel", "SSH", "Copy IP"])
        XCTAssertEqual(actions.map(\.kind), [.dashboard, .ssh, .copyAddress])
    }

    func testDefaultsFollowTheDeviceOperatingSystem() {
        func defaults(_ operatingSystem: String?) -> [String] {
            HostActionCatalog().actions(for: host(id: "h", name: "h", operatingSystem: operatingSystem)).map(\.title)
        }

        XCTAssertEqual(defaults("macOS"), ["SSH", "Screen", "Copy IP"])
        XCTAssertEqual(defaults("linux"), ["SSH", "Copy IP"])
        XCTAssertEqual(defaults("freebsd"), ["SSH", "Copy IP"])
        XCTAssertEqual(defaults("windows"), ["Files", "Copy IP"])
        XCTAssertEqual(defaults("iOS"), ["Copy IP"])
        XCTAssertEqual(defaults("android"), ["Copy IP"])
        XCTAssertEqual(defaults(nil), ["SSH", "Copy IP"])
    }

    func testScreenSharingAndFileSharingOpenSystemURLs() {
        let mac = HostActionCatalog().actions(for: host(id: "m", name: "studio", operatingSystem: "macOS"))
        let windows = HostActionCatalog().actions(for: host(id: "w", name: "stonebook", operatingSystem: "windows"))

        XCTAssertEqual(mac[1].kind, .screenSharing)
        XCTAssertEqual(mac[1].url, URL(string: "vnc://studio.tailnet.ts.net"))
        XCTAssertEqual(windows[0].kind, .fileSharing)
        XCTAssertEqual(windows[0].url, URL(string: "smb://stonebook.tailnet.ts.net"))
    }

    func testConfiguredURLReplacesTheDefaultWithTheSameTarget() {
        let configuration = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(hostID: "studio", actions: [
                TailnetQuickAction(emoji: "🖥", title: "Studio", kind: .url, target: "vnc://studio.tailnet.ts.net"),
            ]),
        ])

        let actions = HostActionCatalog(configuration: configuration)
            .actions(for: host(id: "m", name: "studio", operatingSystem: "macOS"))

        XCTAssertEqual(actions.map(\.title), ["Studio", "SSH", "Copy IP"])
    }

    func testConfiguredURLOpensWithTheMatchingActionKind() {
        let configuration = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(hostID: "studio", actions: [
                TailnetQuickAction(emoji: "🖥", title: "Shell", kind: .url, target: "ssh://monroe@studio.tailnet.ts.net"),
                TailnetQuickAction(emoji: "📁", title: "Share", kind: .url, target: "smb://studio.tailnet.ts.net/Public"),
            ]),
        ])

        let actions = HostActionCatalog(configuration: configuration)
            .actions(for: host(id: "m", name: "studio", operatingSystem: "macOS"))

        XCTAssertEqual(actions[0].kind, .ssh)
        XCTAssertEqual(actions[0].value, "monroe@studio.tailnet.ts.net")
        XCTAssertEqual(actions[1].kind, .fileSharing)
    }

    func testValidationRejectsURLSchemesTheWidgetCannotOpen() {
        let configuration = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(hostID: "h", actions: [
                TailnetQuickAction(emoji: "📦", title: "FTP", kind: .url, target: "ftp://h.tailnet.ts.net"),
                TailnetQuickAction(emoji: "🖥", title: "Screen", kind: .url, target: "vnc://h.tailnet.ts.net"),
            ]),
        ])

        XCTAssertEqual(configuration.validationIssues(), [.invalidURL(hostIndex: 0, actionIndex: 0)])
    }

    func testConfigurationDecodesCustomDashboardLinks() throws {
        let data = Data(
            """
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
            """.utf8
        )

        let configuration = try JSONDecoder().decode(TailnetActionConfiguration.self, from: data)

        XCTAssertEqual(configuration.hostActions.map(\.hostID), ["openclaw"])
        XCTAssertEqual(configuration.hostActions[0].actions.map(\.title), ["Dash", "SSH"])
        XCTAssertEqual(configuration.hostActions[0].actions[0].kind, .url)
        XCTAssertEqual(configuration.hostActions[0].actions[0].target, "http://openclaw.tailnet.ts.net:8080")
    }

    func testConfigurationMatchesHostByMagicDNSName() {
        let configuration = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(hostID: "openclaw.tailnet.ts.net", actions: [
                TailnetQuickAction(emoji: "🧭", title: "Dash", kind: .url, target: "http://openclaw.tailnet.ts.net:8080"),
            ]),
        ])

        XCTAssertEqual(configuration.actions(for: host(id: "peer-1", name: "openclaw")).map(\.title), ["Dash"])
    }

    func testValidationReportsEmptyFields() {
        let configuration = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(hostID: "", actions: [
                TailnetQuickAction(emoji: "", title: "Dash", kind: .url, target: "not-a-url"),
                TailnetQuickAction(emoji: "🖥", title: "SSH", kind: .ssh, target: "ssh://openclaw.tailnet.ts.net"),
                TailnetQuickAction(emoji: "📋", title: "", kind: .copy, target: ""),
            ]),
        ])

        let issues = configuration.validationIssues()

        XCTAssertTrue(issues.contains(.emptyHostID(hostIndex: 0)))
        XCTAssertTrue(issues.contains(.emptyEmoji(hostIndex: 0, actionIndex: 0)))
        XCTAssertTrue(issues.contains(.invalidURL(hostIndex: 0, actionIndex: 0)))
        XCTAssertTrue(issues.contains(.sshTargetContainsScheme(hostIndex: 0, actionIndex: 1)))
        XCTAssertTrue(issues.contains(.emptyTitle(hostIndex: 0, actionIndex: 2)))
        XCTAssertTrue(issues.contains(.emptyTarget(hostIndex: 0, actionIndex: 2)))
    }

    private func host(
        id: String,
        name: String,
        operatingSystem: String? = "linux",
        magicDNSName: String? = nil,
        services: [TailnetService] = []
    ) -> TailnetHost {
        TailnetHost(
            id: id,
            name: name,
            role: .peer,
            status: .online,
            operatingSystem: operatingSystem,
            primaryAddress: "100.64.0.2",
            magicDNSName: magicDNSName ?? "\(name).tailnet.ts.net",
            lastSeen: nil,
            services: services
        )
    }
}
