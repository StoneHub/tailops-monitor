import Foundation

/// When the widget's rendering changes without new data from the host app.
/// The host app reloads the widget after every refresh, so the widget only
/// needs entries for the moments its own display would otherwise go wrong.
public enum TailOpsWidgetSchedule {
    public static let staleInterval: TimeInterval = 90 * 60
    public static let refreshTimeout: TimeInterval = 120
    /// A fallback in case the host app is not running to push reloads.
    public static let safetyReloadInterval: TimeInterval = 6 * 60 * 60

    public static func entryDates(
        now: Date,
        snapshotGeneratedAt: Date?,
        refreshHealth: TailOpsRefreshHealth,
        pendingTransferExpiries: [Date]
    ) -> [Date] {
        var dates = [now]
        if let snapshotGeneratedAt {
            dates.append(snapshotGeneratedAt.addingTimeInterval(staleInterval))
        }
        if refreshHealth.isRefreshInProgress(at: now, timeout: refreshTimeout),
           let lastAttemptAt = refreshHealth.lastAttemptAt {
            dates.append(lastAttemptAt.addingTimeInterval(refreshTimeout))
        }
        dates.append(contentsOf: pendingTransferExpiries)

        return Array(Set(dates.filter { $0 >= now })).sorted()
    }
}
