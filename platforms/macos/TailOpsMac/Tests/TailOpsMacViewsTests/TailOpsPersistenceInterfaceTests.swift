import Foundation
import XCTest
@testable import TailOpsCore
@testable import TailOpsMacViews
@testable import TailOpsShared

final class TailOpsPersistenceInterfaceTests: XCTestCase {
    @MainActor
    func testActionSettingsLoadHostsAndSaveActionsThroughConceptStores() throws {
        let snapshot = TailnetSnapshot(hosts: [Self.host(id: "peer")])
        let configuration = TailnetActionConfiguration(hostActions: [
            TailnetHostActionConfiguration(
                hostID: "peer.tailnet.ts.net",
                actions: [
                    TailnetQuickAction(
                        emoji: "🧭",
                        title: "Dash",
                        kind: .url,
                        target: "http://peer.tailnet.ts.net:8080"
                    )
                ]
            )
        ])
        let store = InMemoryTailOpsStore(
            snapshot: snapshot,
            actionConfiguration: configuration
        )
        let model = TailOpsActionSettingsModel(
            tailnetStore: store,
            settingsStore: store
        )

        XCTAssertEqual(model.hostActions.map(\.hostID), ["peer.tailnet.ts.net"])
        XCTAssertTrue(model.save())

        let settingsStore: any TailOpsSettingsStoring = store
        XCTAssertEqual(try settingsStore.loadActionConfiguration(), model.configuration)
    }

    @MainActor
    func testMonitorConsumesRefreshRequestAndPublishesTailnetState() async throws {
        let request = TailOpsRefreshRequest(requestedAt: Date(timeIntervalSince1970: 100))
        let store = InMemoryTailOpsStore(refreshRequest: request)
        let monitor = TailnetMonitor(
            statusProvider: StaticStatusProvider(),
            tailnetStore: store,
            settingsStore: store,
            requestStore: store
        )

        let didRefresh = await monitor.refreshIfRequested()
        XCTAssertTrue(didRefresh)

        let requestStore: any TailOpsAppGroupRequestStoring = store
        let tailnetStore: any TailnetStateStoring = store
        XCTAssertNil(try requestStore.loadRefreshRequest())
        XCTAssertEqual(try tailnetStore.load()?.hosts.map(\.name), ["monroe-mac", "peer"])
        XCTAssertNotNil(try tailnetStore.loadRefreshHealth()?.lastSuccessAt)
    }

    private static func host(id: String) -> TailnetHost {
        TailnetHost(
            id: id,
            name: id,
            role: .peer,
            status: .online,
            operatingSystem: "macOS",
            primaryAddress: "100.64.0.2",
            magicDNSName: "\(id).tailnet.ts.net",
            lastSeen: nil,
            services: []
        )
    }
}

private struct StaticStatusProvider: TailscaleStatusProviding {
    func statusJSON() async throws -> Data {
        Data(
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
                  "HostName": "peer",
                  "DNSName": "peer.tailnet.ts.net.",
                  "TailscaleIPs": ["100.64.0.2"],
                  "Online": true,
                  "OS": "macOS"
                }
              }
            }
            """.utf8
        )
    }
}
