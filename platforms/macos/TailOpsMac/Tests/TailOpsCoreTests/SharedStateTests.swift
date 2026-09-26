import Foundation
import XCTest
@testable import TailOpsCore
@testable import TailOpsShared

final class SharedStateTests: XCTestCase {
    private var rootURL: URL!
    private var store: SharedSnapshotStore!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "SharedStateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = SharedSnapshotStore(baseURLs: [rootURL])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testWormholeConfigurationRoundTrip() throws {
        let configuration = TailOpsWormholeConfiguration(
            contacts: [
                TailOpsWormholeContact(
                    id: "ben",
                    displayName: "Ben",
                    pairingID: "monroe-ben",
                    createdAt: Date(timeIntervalSince1970: 100)
                ),
            ],
            inboxPath: "~/Desktop/TailOps Inbox"
        )

        try store.saveWormholeConfiguration(configuration)
        let loaded = try store.loadWormholeConfiguration()

        XCTAssertEqual(loaded, configuration)
        XCTAssertEqual(loaded?.contact(id: "ben")?.displayName, "Ben")
    }

    func testWormholeOpenRequestRoundTripsAndClears() throws {
        let request = TailOpsWormholeOpenRequest(
            mode: .receive,
            contactID: "monroe",
            requestedAt: Date(timeIntervalSince1970: 100)
        )

        try store.saveWormholeOpenRequest(request)
        XCTAssertEqual(try store.loadWormholeOpenRequest(), request)

        try store.clearWormholeOpenRequest()
        XCTAssertNil(try store.loadWormholeOpenRequest())
    }

    func testWormholePendingTransfersRoundTrip() throws {
        let transfer = TailOpsWormholePendingTransfer(
            id: "transfer-1",
            contactID: "ben",
            pairingID: "monroe-ben",
            senderName: "Monroe",
            fileName: "prompt.md",
            fileSizeBytes: 42,
            direction: .incoming,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )

        try store.saveWormholePendingTransfers([transfer])

        XCTAssertEqual(try store.loadWormholePendingTransfers(), [transfer])
    }

    func testSignalURLsUseTailOpsScheme() {
        XCTAssertEqual(TailOpsSettingsOpenSignal.url.scheme, "tailops")
        XCTAssertEqual(TailOpsSettingsOpenSignal.url.host, "settings")
        XCTAssertEqual(TailOpsWormholeSignal.url.scheme, "tailops")
        XCTAssertEqual(TailOpsWormholeSignal.url.host, "wormhole")
    }

    func testWormholeCodeFactoryDerivesSharedWindowCodes() {
        let monroeContact = TailOpsWormholeContact(id: "ben", displayName: "Ben", pairingID: "monroe-ben")
        let benContact = TailOpsWormholeContact(id: "monroe", displayName: "Monroe", pairingID: "monroe-ben")
        let factory = TailOpsWormholeCodeFactory(windowDuration: 900)
        let date = Date(timeIntervalSince1970: 1_800)

        let senderCode = factory.code(for: monroeContact, sharedSecret: "tailops test secret", date: date)
        let receiverCode = factory.code(for: benContact, sharedSecret: "tailops test secret", date: date.addingTimeInterval(60))
        let nextWindowCode = factory.code(for: monroeContact, sharedSecret: "tailops test secret", date: date.addingTimeInterval(901))
        let candidates = factory.candidateCodes(
            for: benContact,
            sharedSecret: "tailops test secret",
            date: date.addingTimeInterval(901),
            skewTolerance: 1
        )

        XCTAssertEqual(senderCode.code, receiverCode.code)
        XCTAssertNotEqual(senderCode.code, nextWindowCode.code)
        XCTAssertTrue(candidates.map(\.code).contains(senderCode.code))
        XCTAssertEqual(senderCode.code.split(separator: "-").count, 5)
    }
}
