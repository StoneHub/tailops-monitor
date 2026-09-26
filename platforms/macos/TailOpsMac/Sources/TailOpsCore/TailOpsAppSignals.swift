import Foundation

public struct TailOpsRefreshRequest: Codable, Equatable, Sendable {
    public let requestedAt: Date

    public init(requestedAt: Date = Date()) {
        self.requestedAt = requestedAt
    }
}

public struct TailOpsRefreshHealth: Codable, Equatable, Sendable {
    public let lastAttemptAt: Date?
    public let lastSuccessAt: Date?
    public let lastError: String?

    public init(lastAttemptAt: Date? = nil, lastSuccessAt: Date? = nil, lastError: String? = nil) {
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
    }

    public var hasFailedSinceLastSuccess: Bool {
        guard lastError != nil, let lastAttemptAt else { return false }
        guard let lastSuccessAt else { return true }
        return lastAttemptAt > lastSuccessAt
    }

    public var isRefreshInProgress: Bool {
        guard lastError == nil, let lastAttemptAt else { return false }
        guard let lastSuccessAt else { return true }
        return lastAttemptAt > lastSuccessAt
    }

    public func isRefreshInProgress(at date: Date, timeout: TimeInterval = 120) -> Bool {
        guard isRefreshInProgress, let lastAttemptAt else { return false }
        return date.timeIntervalSince(lastAttemptAt) < timeout
    }
}

public enum TailOpsRefreshSignal {
    public static let notificationName = "dev.tailops.monitor.refresh"
}

public enum TailOpsSettingsOpenSignal {
    public static let url = URL(string: "tailops://settings")!
}

public enum TailOpsWormholeSignal {
    public static let notificationName = "dev.tailops.monitor.openWormhole"
    public static let url = URL(string: "tailops://wormhole")!
}

public struct TailOpsWormholeOpenRequest: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Equatable, Sendable {
        case send
        case receive
    }

    public let mode: Mode
    public let contactID: String?
    public let pendingTransferID: String?
    public let requestedAt: Date

    public init(mode: Mode, contactID: String? = nil, pendingTransferID: String? = nil, requestedAt: Date = Date()) {
        self.mode = mode
        self.contactID = contactID
        self.pendingTransferID = pendingTransferID
        self.requestedAt = requestedAt
    }
}
