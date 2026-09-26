import Foundation
import XCTest
@testable import TailOpsMacViews

final class BoundedProcessRunnerTests: XCTestCase {
    func testOutputWithinLimitIsCompleteAndNotFlagged() async throws {
        let result = try await run("printf 'hello'", maximumOutputBytes: 64)

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "hello")
        XCTAssertFalse(result.stdoutWasTruncated)
    }

    func testOversizedOutputKeepsNewestBytesAndIsFlagged() async throws {
        let result = try await run("printf '1234567890'", maximumOutputBytes: 4)

        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "7890")
        XCTAssertTrue(result.stdoutWasTruncated)
    }

    func testChildReadsEndOfFileFromStandardInput() async throws {
        let result = try await run("cat; printf 'done'", maximumOutputBytes: 64, timeout: 5)

        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "done")
    }

    func testTimeoutTerminatesTheChild() async throws {
        do {
            _ = try await run("sleep 30", maximumOutputBytes: 64, timeout: 0.5)
            XCTFail("Expected a timeout")
        } catch BoundedProcessRunnerError.timedOut {
        }
    }

    private func run(
        _ script: String,
        maximumOutputBytes: Int,
        timeout: TimeInterval = 10
    ) async throws -> BoundedProcessResult {
        try await BoundedProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: timeout,
            maximumStandardOutputBytes: maximumOutputBytes,
            maximumStandardErrorBytes: 1_024
        )
    }
}
