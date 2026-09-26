import SwiftUI
import WidgetKit
import XCTest
@testable import TailOpsCore
@testable import TailOpsShared
@testable import TailOpsWidgetViews

/// Guards against content growing past the widget's height, which WidgetKit
/// clips silently at the bottom edge. Heights are the documented macOS widget
/// sizes; ImageRenderer approximates WidgetKit layout, so keep some margin.
@MainActor
final class WidgetLayoutFitTests: XCTestCase {
    private let families: [(WidgetFamily, CGSize)] = [
        (.systemMedium, CGSize(width: 364, height: 170)),
        (.systemLarge, CGSize(width: 364, height: 382)),
        (.systemExtraLarge, CGSize(width: 780, height: 382)),
    ]

    func testBusiestTailnetFitsEveryFamilyWithAndWithoutBanner() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let hosts = (1...10).map { index in
            TailnetHost(
                id: "peer-\(index)",
                name: "workstation-\(index).example",
                role: .peer,
                status: index == 3 ? .warning : .online,
                operatingSystem: "macOS",
                primaryAddress: "100.64.0.\(index)",
                magicDNSName: "workstation-\(index).tailnet.ts.net",
                lastSeen: nil,
                services: [],
                diagnostics: TailnetHostDiagnostics(ping: TailnetPingSummary(samples: [
                    TailnetPingSample(latencyMilliseconds: 142, route: .derp),
                ])),
                connection: .derp(region: "mia"),
                keyExpiry: index == 3 ? now.addingTimeInterval(3 * 24 * 60 * 60) : nil
            )
        }
        let banners: [TailnetHealth?] = [
            nil,
            TailnetHealth(backendState: "Running", warnings: [String(repeating: "Long health warning ", count: 8)]),
        ]

        for health in banners {
            let entry = TailOpsEntry(
                date: now,
                snapshot: TailnetSnapshot(hosts: hosts, generatedAt: now, health: health),
                actionConfiguration: TailnetActionConfiguration(),
                refreshHealth: TailOpsRefreshHealth(lastAttemptAt: now, lastSuccessAt: now),
                wormholeConfiguration: TailOpsWormholeConfiguration(),
                pendingWormholeTransfers: []
            )
            for (family, size) in families {
                let view = TailOpsWidgetView(entry: entry, family: family)
                    .frame(width: size.width)
                    .fixedSize(horizontal: false, vertical: true)
                let height = try XCTUnwrap(ImageRenderer(content: view).nsImage?.size.height)

                XCTAssertLessThanOrEqual(
                    height,
                    size.height,
                    "\(family) content is \(Int(height))pt tall (banner: \(health != nil))"
                )
            }
        }
    }
}
