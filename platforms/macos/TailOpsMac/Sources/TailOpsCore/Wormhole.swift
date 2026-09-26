import CryptoKit
import Foundation

public struct TailOpsWormholeConfiguration: Codable, Equatable, Sendable {
    public let contacts: [TailOpsWormholeContact]
    public let inboxPath: String
    public let pendingSignalPort: Int?

    public init(
        contacts: [TailOpsWormholeContact] = [],
        inboxPath: String = "~/Desktop/TailOps Inbox",
        pendingSignalPort: Int? = 39117
    ) {
        self.contacts = contacts
        self.inboxPath = inboxPath
        self.pendingSignalPort = pendingSignalPort
    }

    public func contact(id: String) -> TailOpsWormholeContact? {
        contacts.first { $0.id == id }
    }
}

public struct TailOpsWormholePendingTransfer: Codable, Equatable, Identifiable, Sendable {
    public enum Direction: String, Codable, Equatable, Sendable {
        case outgoing
        case incoming
    }

    public let id: String
    public let contactID: String?
    public let pairingID: String
    public let senderName: String
    public let fileName: String
    public let fileSizeBytes: Int64?
    public let direction: Direction
    public let createdAt: Date
    public let expiresAt: Date

    public init(
        id: String = UUID().uuidString,
        contactID: String?,
        pairingID: String,
        senderName: String,
        fileName: String,
        fileSizeBytes: Int64? = nil,
        direction: Direction,
        createdAt: Date = Date(),
        expiresAt: Date
    ) {
        self.id = id
        self.contactID = contactID
        self.pairingID = pairingID
        self.senderName = senderName
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.direction = direction
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        expiresAt <= date
    }
}

public struct TailOpsWormholeContact: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let pairingID: String
    public let tailnetNodeID: String?
    public let createdAt: Date

    public init(
        id: String,
        displayName: String,
        pairingID: String,
        tailnetNodeID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.pairingID = pairingID
        self.tailnetNodeID = tailnetNodeID
        self.createdAt = createdAt
    }
}

public struct TailOpsWormholeSignalReplayRecord: Codable, Equatable, Sendable {
    public let messageID: String
    public let expiresAt: Date

    public init(messageID: String, expiresAt: Date) {
        self.messageID = messageID
        self.expiresAt = expiresAt
    }
}

public struct TailOpsWormholeTransferCode: Codable, Equatable, Sendable {
    public let code: String
    public let validFrom: Date
    public let validUntil: Date

    public init(code: String, validFrom: Date, validUntil: Date) {
        self.code = code
        self.validFrom = validFrom
        self.validUntil = validUntil
    }
}

public struct TailOpsWormholeCodeFactory: Sendable {
    public let windowDuration: TimeInterval

    public init(windowDuration: TimeInterval = 900) {
        self.windowDuration = max(windowDuration, 60)
    }

    public func code(
        for contact: TailOpsWormholeContact,
        sharedSecret: String,
        date: Date = Date(),
        purpose: String = "file-transfer-v1"
    ) -> TailOpsWormholeTransferCode {
        code(
            for: contact,
            sharedSecret: sharedSecret,
            windowIndex: windowIndex(for: date),
            purpose: purpose
        )
    }

    public func candidateCodes(
        for contact: TailOpsWormholeContact,
        sharedSecret: String,
        date: Date = Date(),
        skewTolerance: Int = 1,
        purpose: String = "file-transfer-v1"
    ) -> [TailOpsWormholeTransferCode] {
        let currentWindow = windowIndex(for: date)
        let tolerance = max(skewTolerance, 0)
        return (-tolerance...tolerance).map { offset in
            code(
                for: contact,
                sharedSecret: sharedSecret,
                windowIndex: currentWindow + Int64(offset),
                purpose: purpose
            )
        }
    }

    private func code(
        for contact: TailOpsWormholeContact,
        sharedSecret: String,
        windowIndex: Int64,
        purpose: String
    ) -> TailOpsWormholeTransferCode {
        let secret = SymmetricKey(data: Data(sharedSecret.utf8))
        let message = "\(purpose):\(contact.pairingID):\(windowIndex)"
        let digest = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: secret)
        let bytes = Array(digest)
        let nameplate = Int(bytes[0]) << 8 | Int(bytes[1])
        let words = stride(from: 2, to: 10, by: 2).map { offset in
            let value = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            return Self.wordList[value % Self.wordList.count]
        }
        let code = ([String((nameplate % 999) + 1)] + words).joined(separator: "-")
        let validFrom = Date(timeIntervalSince1970: TimeInterval(windowIndex) * windowDuration)
        return TailOpsWormholeTransferCode(
            code: code,
            validFrom: validFrom,
            validUntil: validFrom.addingTimeInterval(windowDuration)
        )
    }

    private func windowIndex(for date: Date) -> Int64 {
        Int64(floor(date.timeIntervalSince1970 / windowDuration))
    }

    private static let wordList = [
        "amber", "anchor", "apple", "atlas", "baker", "beacon", "berry", "bridge",
        "cable", "cedar", "clover", "copper", "delta", "drift", "ember", "falcon",
        "field", "forest", "garden", "glade", "harbor", "hollow", "island", "jacket",
        "kernel", "lantern", "maple", "meadow", "mesa", "mirror", "north", "novel",
        "ocean", "orbit", "paper", "pepper", "pilot", "prairie", "quartz", "quiet",
        "raven", "river", "rocket", "saddle", "silver", "signal", "stone", "summit",
        "thread", "timber", "tunnel", "valley", "velvet", "violet", "walnut", "wander",
        "water", "willow", "window", "winter", "yellow", "yonder", "zenith", "zero"
    ]
}
