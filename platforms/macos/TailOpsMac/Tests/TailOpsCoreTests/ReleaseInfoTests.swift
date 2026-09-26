import Foundation
import XCTest
@testable import TailOpsCore

final class ReleaseInfoTests: XCTestCase {
    func testSemanticVersionOrdersNumerically() throws {
        let a = try XCTUnwrap(SemanticVersion.parse("1.1.0"))
        let b = try XCTUnwrap(SemanticVersion.parse("1.1.10"))
        let c = try XCTUnwrap(SemanticVersion.parse("1.2.0"))

        XCTAssertLessThan(a, b)
        XCTAssertLessThan(b, c)
        XCTAssertEqual(SemanticVersion.parse("v1.2.3"), SemanticVersion.parse("1.2.3"))
        XCTAssertEqual(SemanticVersion.parse("1.0"), SemanticVersion.parse("1.0.0"))
        XCTAssertEqual(Set([SemanticVersion.parse("1.0"), SemanticVersion.parse("1.0.0")]).count, 1)
        XCTAssertEqual(SemanticVersion.parse("1.2.3")?.description, "1.2.3")
        XCTAssertNil(SemanticVersion.parse("junk"))
        XCTAssertNil(SemanticVersion.parse("1.2.x"))
        XCTAssertNil(SemanticVersion.parse("1..2"))
        XCTAssertNil(SemanticVersion.parse("v"))
    }

    // Field names follow https://docs.github.com/en/rest/releases/releases#list-releases.
    func testNewestPicksTheHighestPublishedVersionWithATailOpsAsset() throws {
        let list = Data(
            """
            [
              {"tag_name": "v1.1.0", "html_url": "https://github.com/StoneHub/tailops-monitor/releases/tag/v1.1.0",
               "draft": false, "prerelease": true, "body": "# TailOps 1.1.0\\n\\nShows tailnet status in the widget.\\n",
               "assets": [
                 {"name": "TailOps-1.1.0.zip.sha256", "browser_download_url": "https://example.com/TailOps-1.1.0.zip.sha256", "size": 80},
                 {"name": "TailOps-1.1.0.zip", "browser_download_url": "https://example.com/TailOps-1.1.0.zip", "size": 4096000}
               ]},
              {"tag_name": "v1.3.0", "html_url": "https://example.com/draft", "draft": true, "body": "draft",
               "assets": [{"name": "TailOps-1.3.0.zip", "browser_download_url": "https://example.com/TailOps-1.3.0.zip", "size": 1}]},
              {"tag_name": "v1.2.0", "html_url": "https://example.com/no-asset", "draft": false, "body": "", "assets": []},
              {"tag_name": "browser-dashboard-final", "html_url": "https://example.com/tag", "draft": false, "body": "", "assets": []}
            ]
            """.utf8
        )

        let release = try ReleaseInfo.newest(from: list)

        XCTAssertEqual(release.tag, "v1.1.0")
        XCTAssertEqual(release.version, SemanticVersion.parse("1.1.0"))
        XCTAssertEqual(release.downloadURL.lastPathComponent, "TailOps-1.1.0.zip")
        XCTAssertEqual(release.assetSize, 4_096_000)
        XCTAssertEqual(release.firstNoteLine, "Shows tailnet status in the widget.")
    }

    func testNewestReportsWhenNothingIsInstallable() {
        XCTAssertThrowsError(try ReleaseInfo.newest(from: Data("[]".utf8))) { error in
            XCTAssertEqual(error as? ReleaseInfo.ParseError, .noRelease)
        }
        XCTAssertThrowsError(try ReleaseInfo.newest(from: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? ReleaseInfo.ParseError, .badJSON)
        }
    }
}
