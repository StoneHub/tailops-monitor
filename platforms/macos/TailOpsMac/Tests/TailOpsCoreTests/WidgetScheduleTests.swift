import Foundation
import XCTest
@testable import TailOpsCore

final class WidgetScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testSettledSnapshotSchedulesOnlyTheStaleMoment() {
        let generatedAt = now.addingTimeInterval(-60)

        let dates = TailOpsWidgetSchedule.entryDates(
            now: now,
            snapshotGeneratedAt: generatedAt,
            refreshHealth: TailOpsRefreshHealth(lastAttemptAt: generatedAt, lastSuccessAt: generatedAt),
            pendingTransferExpiries: []
        )

        XCTAssertEqual(dates, [now, generatedAt.addingTimeInterval(TailOpsWidgetSchedule.staleInterval)])
    }

    func testRefreshInProgressAndPendingExpiriesAddEntriesInOrder() {
        let attempt = now.addingTimeInterval(-30)
        let expiry = now.addingTimeInterval(600)

        let dates = TailOpsWidgetSchedule.entryDates(
            now: now,
            snapshotGeneratedAt: nil,
            refreshHealth: TailOpsRefreshHealth(lastAttemptAt: attempt),
            pendingTransferExpiries: [expiry, now.addingTimeInterval(-5)]
        )

        XCTAssertEqual(dates, [now, attempt.addingTimeInterval(TailOpsWidgetSchedule.refreshTimeout), expiry])
    }

    func testAlreadyStaleSnapshotAddsNoPastEntries() {
        let dates = TailOpsWidgetSchedule.entryDates(
            now: now,
            snapshotGeneratedAt: now.addingTimeInterval(-3 * 60 * 60),
            refreshHealth: TailOpsRefreshHealth(),
            pendingTransferExpiries: []
        )

        XCTAssertEqual(dates, [now])
    }
}
