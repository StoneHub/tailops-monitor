import Foundation

/// A Linux Fleet node's own health, as reported by its `tailopsd` collector in the
/// health-only `tailops.host-health` document.
public struct TailnetNodeHealth: Codable, Equatable, Sendable {
    public let collector: String
    public let observedAt: Date
    public let uptimeSeconds: Int?
    public let memoryAvailableRatio: Double?
    public let rootDiskUsedRatio: Double?
    public let failedUnits: [String]
    public let temperatureCelsius: Double?
    public let warnings: [String]
    /// Set when the reading is older than `staleInterval`, e.g. because the node's
    /// timer stopped or TailOps could not fetch a newer one.
    public let isStale: Bool

    /// tailopsd writes every 15 minutes; three missed runs make a reading stale.
    public static let staleInterval: TimeInterval = 45 * 60

    public init(
        collector: String,
        observedAt: Date,
        uptimeSeconds: Int? = nil,
        memoryAvailableRatio: Double? = nil,
        rootDiskUsedRatio: Double? = nil,
        failedUnits: [String] = [],
        temperatureCelsius: Double? = nil,
        warnings: [String] = [],
        isStale: Bool = false
    ) {
        self.collector = collector
        self.observedAt = observedAt
        self.uptimeSeconds = uptimeSeconds
        self.memoryAvailableRatio = memoryAvailableRatio
        self.rootDiskUsedRatio = rootDiskUsedRatio
        self.failedUnits = failedUnits
        self.temperatureCelsius = temperatureCelsius
        self.warnings = warnings
        self.isStale = isStale
    }

    public func checkingStaleness(at date: Date) -> TailnetNodeHealth {
        TailnetNodeHealth(
            collector: collector,
            observedAt: observedAt,
            uptimeSeconds: uptimeSeconds,
            memoryAvailableRatio: memoryAvailableRatio,
            rootDiskUsedRatio: rootDiskUsedRatio,
            failedUnits: failedUnits,
            temperatureCelsius: temperatureCelsius,
            warnings: warnings,
            isStale: date.timeIntervalSince(observedAt) > Self.staleInterval
        )
    }

    /// Fresh warnings that should turn the host into a warning.
    public var activeWarnings: [String] {
        isStale ? [] : warnings
    }

    /// One short line for the widget, e.g. "Healthy · 37 °C · disk 45%".
    public var summaryText: String {
        if isStale {
            return "Health reading is stale"
        }
        if let warning = warnings.first {
            return warnings.count > 1 ? "\(warning) (+\(warnings.count - 1))" : warning
        }
        var parts = ["Healthy"]
        if let temperatureCelsius {
            parts.append("\(Int(temperatureCelsius.rounded())) °C")
        }
        if let rootDiskUsedRatio {
            parts.append("disk \(Int((rootDiskUsedRatio * 100).rounded()))%")
        }
        return parts.joined(separator: " · ")
    }

    public func matches(_ host: TailnetHost) -> Bool {
        let name = collector.lowercased()
        return host.name.lowercased() == name
            || host.magicDNSName?.lowercased().hasPrefix(name + ".") == true
    }
}

public enum TailnetNodeHealthError: LocalizedError, Equatable {
    case notHealthDocument
    case missingHost

    public var errorDescription: String? {
        switch self {
        case .notHealthDocument:
            return "The node did not return a TailOps health document."
        case .missingHost:
            return "The node's health document has no host section."
        }
    }
}

public struct TailnetNodeHealthParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> TailnetNodeHealth {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.kind == "tailops.host-health", document.schemaVersion == 1,
              let observedAt = Self.parseDate(document.observedAt)
        else {
            throw TailnetNodeHealthError.notHealthDocument
        }
        guard let host = document.host else { throw TailnetNodeHealthError.missingHost }

        let memoryRatio = host.memory.flatMap { memory in
            memory.totalBytes > 0 ? Double(memory.availableBytes) / Double(memory.totalBytes) : nil
        }
        let rootDisk = host.disks?.first { $0.mount == "/" }
        let diskRatio = rootDisk.flatMap { disk in
            disk.totalBytes > 0 ? 1 - Double(disk.availableBytes) / Double(disk.totalBytes) : nil
        }
        return TailnetNodeHealth(
            collector: document.collector?.node ?? host.hostname ?? "unknown",
            observedAt: observedAt,
            uptimeSeconds: host.uptimeSeconds,
            memoryAvailableRatio: memoryRatio,
            rootDiskUsedRatio: diskRatio,
            failedUnits: host.failedUnits ?? [],
            temperatureCelsius: host.temperatureCelsius,
            warnings: host.warnings ?? []
        )
    }

    /// tailopsd writes JavaScript ISO timestamps, which carry milliseconds.
    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private struct Document: Decodable {
        struct Collector: Decodable {
            let node: String?
        }

        struct Host: Decodable {
            struct Memory: Decodable {
                let totalBytes: Int64
                let availableBytes: Int64
            }

            struct Disk: Decodable {
                let mount: String
                let totalBytes: Int64
                let availableBytes: Int64
            }

            let hostname: String?
            let uptimeSeconds: Int?
            let memory: Memory?
            let disks: [Disk]?
            let failedUnits: [String]?
            let temperatureCelsius: Double?
            let warnings: [String]?
        }

        let schemaVersion: Int
        let kind: String
        let observedAt: String
        let collector: Collector?
        let host: Host?
    }
}
