import Foundation
import Network
import XCTest
@testable import TailOpsCore
@testable import TailOpsMacViews

final class TailOpsWormholeListenerBoundaryTests: XCTestCase {
    func testOnlyTailnetAddressesMayConnect() {
        XCTAssertTrue(isTailnet("100.64.0.1"))
        XCTAssertTrue(isTailnet("100.127.255.254"))
        XCTAssertTrue(isTailnet("fd7a:115c:a1e0::1"))
        XCTAssertTrue(isTailnet("::ffff:100.100.1.1"))

        XCTAssertFalse(isTailnet("100.63.255.255"))
        XCTAssertFalse(isTailnet("100.128.0.1"))
        XCTAssertFalse(isTailnet("192.168.1.20"))
        XCTAssertFalse(isTailnet("127.0.0.1"))
        XCTAssertFalse(isTailnet("fe80::1"))
        XCTAssertFalse(isTailnet("::ffff:192.168.1.20"))
    }

    func testPortValidationRejectsOutOfRangeValuesInsteadOfTrapping() {
        XCTAssertEqual(TailOpsWormholePendingSignalServer.port(from: nil)?.rawValue, 39117)
        XCTAssertEqual(TailOpsWormholePendingSignalServer.port(from: 40000)?.rawValue, 40000)
        XCTAssertNil(TailOpsWormholePendingSignalServer.port(from: 0))
        XCTAssertNil(TailOpsWormholePendingSignalServer.port(from: -1))
        XCTAssertNil(TailOpsWormholePendingSignalServer.port(from: 70_000))
    }

    @MainActor
    func testMalformedPeerResponsesAreRejectedInsteadOfTrapping() {
        let emptyLength = Data("HTTP/1.1 201 Created\r\nContent-Length:\r\n\r\n".utf8)
        let bareStatus = Data("HTTP/1.1 \r\nContent-Length: 0\r\n\r\n".utf8)

        XCTAssertFalse(TailOpsWormholePendingSignalClient.responseIsComplete(emptyLength))
        XCTAssertThrowsError(try TailOpsWormholePendingSignalClient.parseResponseStatus(bareStatus))
        XCTAssertEqual(
            try TailOpsWormholePendingSignalClient.parseResponseStatus(
                Data("HTTP/1.1 409 Conflict\r\nContent-Length: 0\r\n\r\n".utf8)
            ),
            409
        )
    }

    func testStaleWormholeOpenRequestsAreIgnored() {
        let request = TailOpsWormholeOpenRequest(mode: .receive, requestedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertTrue(request.isFresh(at: Date(timeIntervalSince1970: 1_060)))
        XCTAssertFalse(request.isFresh(at: Date(timeIntervalSince1970: 1_000 + 3_600)))
    }

    private func isTailnet(_ address: String) -> Bool {
        TailOpsWormholePendingSignalServer.isTailnetAddress(.hostPort(host: NWEndpoint.Host(address), port: 39117))
    }
}
