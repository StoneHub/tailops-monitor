import Foundation

public struct TailnetPingSummary: Codable, Equatable, Sendable {
    public let samples: [TailnetPingSample]
    public let lastUpdated: Date

    public init(samples: [TailnetPingSample], lastUpdated: Date = Date()) {
        self.samples = samples
        self.lastUpdated = lastUpdated
    }

    public var latestRoute: TailnetPingRoute {
        samples.last?.route ?? .unknown
    }

    public var latestLatencyMilliseconds: Double? {
        samples.last?.latencyMilliseconds
    }

    public var averageLatencyMilliseconds: Double? {
        guard !samples.isEmpty else {
            return nil
        }

        let total = samples.reduce(0) { partial, sample in
            partial + sample.latencyMilliseconds
        }
        return total / Double(samples.count)
    }

    public func mergingRecentSamples(from newerSummary: TailnetPingSummary, maxSamples: Int) -> TailnetPingSummary {
        let sampleLimit = max(maxSamples, 0)
        let retainedSamples = Array((samples + newerSummary.samples).suffix(sampleLimit))
        return TailnetPingSummary(samples: retainedSamples, lastUpdated: newerSummary.lastUpdated)
    }
}

public struct TailnetPingSample: Codable, Equatable, Sendable {
    public let latencyMilliseconds: Double
    public let route: TailnetPingRoute

    public init(latencyMilliseconds: Double, route: TailnetPingRoute) {
        self.latencyMilliseconds = latencyMilliseconds
        self.route = route
    }
}

public enum TailnetPingRoute: String, Codable, Equatable, Sendable {
    case direct
    case peerRelay
    case derp
    case unknown

    public var label: String {
        switch self {
        case .direct:
            return "Direct"
        case .peerRelay:
            return "Peer relay"
        case .derp:
            return "DERP"
        case .unknown:
            return "Unknown"
        }
    }
}

public struct TailnetPingOutputParser: Sendable {
    public init() {}

    public func parse(_ output: String, lastUpdated: Date = Date()) -> TailnetPingSummary? {
        let samples = output
            .split(separator: "\n")
            .compactMap { Self.parseLine(String($0)) }

        guard !samples.isEmpty else { return nil }
        return TailnetPingSummary(samples: samples, lastUpdated: lastUpdated)
    }

    private static func parseLine(_ line: String) -> TailnetPingSample? {
        guard line.contains("pong from"), line.contains(" in ") else {
            return nil
        }

        let route = route(from: line)
        guard let latency = latencyMilliseconds(from: line) else {
            return nil
        }

        return TailnetPingSample(latencyMilliseconds: latency, route: route)
    }

    private static func route(from line: String) -> TailnetPingRoute {
        if line.contains("via DERP(") {
            return .derp
        }
        if line.contains("via peer-relay(") {
            return .peerRelay
        }
        if line.contains("via ") {
            return .direct
        }
        return .unknown
    }

    private static func latencyMilliseconds(from line: String) -> Double? {
        guard let range = line.range(of: " in ") else { return nil }
        let rawValue = line[range.upperBound...]
            .split(separator: " ")
            .first
            .map(String.init) ?? ""

        if rawValue.hasSuffix("ms") {
            return Double(rawValue.dropLast(2))
        }
        if rawValue.hasSuffix("s") {
            return Double(rawValue.dropLast()).map { $0 * 1_000 }
        }
        if rawValue.hasSuffix("µs") {
            return Double(rawValue.dropLast(2)).map { $0 / 1_000 }
        }
        return nil
    }
}
