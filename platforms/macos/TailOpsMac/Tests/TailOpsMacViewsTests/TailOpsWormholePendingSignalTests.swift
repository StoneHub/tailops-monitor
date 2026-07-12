import Foundation
import XCTest
@testable import TailOpsCore
@testable import TailOpsMacViews
@testable import TailOpsShared

final class TailOpsWormholePendingSignalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let secret = "test-only-secret"

    func testPayloadAndPendingStoreNeverContainTransferCode() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SharedSnapshotStore(baseURLs: [root])
        let transfer = pendingTransfer()
        let payload = try TailOpsWormholePendingSignalServer.encoder.encode(
            TailOpsWormholePendingSignalPayload(transfer: transfer)
        )
        try store.saveWormholePendingTransfers([transfer])
        let persisted = try Data(contentsOf: root.appending(path: "tailops-wormhole-pending.json"))

        XCTAssertNil(String(data: payload, encoding: .utf8)?.range(of: "\"code\""))
        XCTAssertNil(String(data: persisted, encoding: .utf8)?.range(of: "\"code\""))
    }

    func testLegacyPendingFileIsSanitizedOnLoad() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = """
        [{"id":"00000000-0000-0000-0000-000000000001","contactID":"ben","pairingID":"pair","senderName":"Monroe","fileName":"a.txt","fileSizeBytes":1,"code":"SECRET-CODE","direction":"incoming","createdAt":"2033-05-18T03:31:00Z","expiresAt":"2033-05-18T03:35:00Z"}]
        """
        let url = root.appending(path: "tailops-wormhole-pending.json")
        try Data(legacy.utf8).write(to: url)

        _ = try SharedSnapshotStore(baseURLs: [root]).loadWormholePendingTransfers()

        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("SECRET-CODE"))
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("\"code\""))
    }

    func testValidRequestAcknowledgesOnceAndRejectsReplay() throws {
        let (server, body) = try configuredServerAndBody()
        let request = request(body: body, signature: TailOpsWormholePendingSignalServer.signature(for: body, secret: secret))

        let acknowledgement = try server.accept(request, now: now)

        XCTAssertEqual(acknowledgement.messageID, pendingTransfer().id)
        XCTAssertThrowsError(try server.accept(request, now: now)) { error in
            guard let signalError = error as? TailOpsWormholePendingSignalError,
                  case .replay = signalError
            else {
                return XCTFail("Expected replay rejection, got \(error)")
            }
        }
    }

    func testTamperedSignatureAndInvalidTimesAreRejected() throws {
        let (server, body) = try configuredServerAndBody()
        XCTAssertThrowsError(try server.accept(request(body: body, signature: String(repeating: "0", count: 64)), now: now))

        let expired = TailOpsWormholePendingTransfer(
            id: UUID().uuidString, contactID: "ben", pairingID: "pair", senderName: "Monroe",
            fileName: "a.txt", direction: .incoming,
            createdAt: now.addingTimeInterval(-1_000), expiresAt: now.addingTimeInterval(-1)
        )
        let expiredBody = try TailOpsWormholePendingSignalServer.encoder.encode(TailOpsWormholePendingSignalPayload(transfer: expired))
        XCTAssertThrowsError(try server.accept(request(body: expiredBody, signature: TailOpsWormholePendingSignalServer.signature(for: expiredBody, secret: secret)), now: now))
    }

    func testStrictParserRejectsWrongMethodDuplicateLengthAndOversizeHeader() throws {
        let (_, body) = try configuredServerAndBody()
        let signature = TailOpsWormholePendingSignalServer.signature(for: body, secret: secret)
        XCTAssertThrowsError(try TailOpsWormholePendingSignalServer.expectedRequestLength(
            Data(request(body: body, signature: signature).dropFirst(1))
        ))
        let duplicate = request(body: body, signature: signature, extraHeader: "Content-Length: \(body.count)\r\n")
        XCTAssertThrowsError(try TailOpsWormholePendingSignalServer.expectedRequestLength(duplicate))
        let oversized = Data(("POST /wormhole/pending HTTP/1.1\r\nX-Fill: " + String(repeating: "a", count: 9_000)).utf8)
        XCTAssertThrowsError(try TailOpsWormholePendingSignalServer.expectedRequestLength(oversized))
    }

    private func configuredServerAndBody() throws -> (TailOpsWormholePendingSignalServer, Data) {
        let root = temporaryRoot()
        let store = SharedSnapshotStore(baseURLs: [root])
        try store.saveWormholeConfiguration(.init(contacts: [
            .init(id: "ben", displayName: "Ben", pairingID: "pair", tailnetNodeID: "peer-1")
        ]))
        let server = TailOpsWormholePendingSignalServer(store: store, secretStore: TestSecretStore(secret: secret))
        let body = try TailOpsWormholePendingSignalServer.encoder.encode(
            TailOpsWormholePendingSignalPayload(transfer: pendingTransfer())
        )
        return (server, body)
    }

    private func pendingTransfer() -> TailOpsWormholePendingTransfer {
        .init(
            id: "00000000-0000-0000-0000-000000000001", contactID: "ben", pairingID: "pair",
            senderName: "Monroe", fileName: "a.txt", fileSizeBytes: 1, direction: .outgoing,
            createdAt: now, expiresAt: now.addingTimeInterval(15 * 60)
        )
    }

    private func request(body: Data, signature: String, extraHeader: String = "") -> Data {
        let header = "POST /wormhole/pending HTTP/1.1\r\nHost: peer\r\nContent-Type: application/json\r\nX-TailOps-Signature: \(signature)\r\n\(extraHeader)Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + body
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "TailOpsSignalTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private struct TestSecretStore: TailOpsWormholeSecretStoring {
    let secret: String
    func secret(for contactID: String) throws -> String? { secret }
    func save(secret: String, for contactID: String) throws {}
}
