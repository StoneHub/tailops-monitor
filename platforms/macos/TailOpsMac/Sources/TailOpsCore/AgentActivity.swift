import Foundation

/// What the Fleet agent observer on one host reported when TailOps last asked: how many
/// coding agents (Claude Code, Codex, OpenClaw) are working or waiting for you.
///
/// The observer writes a counts-only `fleet.agent-summary/1` file beside its full
/// `fleet.agent-state/1` state. TailOps reads this Mac's copy on every refresh (one local
/// file read) and another host's only when you ask (the widget's refresh button), over
/// HTTPS from the read-only file that host shares on the tailnet with Tailscale Serve.
/// A reading is shown for `displayInterval` after it was taken and then drops off the
/// tile, so an old count never looks live.
public struct TailnetAgentActivity: Codable, Equatable, Sendable {
    /// The tailnet host name the reading came from; nil for this Mac's own observer.
    public let source: String?
    /// The observer's host name (`host` in the state document).
    public let collector: String
    /// When the observer last wrote its state.
    public let generatedAt: Date
    /// When TailOps read it.
    public let readAt: Date
    public let working: Int
    public let waiting: Int
    public let idle: Int
    /// Harnesses of the agents that are working or waiting, sorted, e.g. ["claude-code", "openclaw"].
    public let activeHarnesses: [String]

    /// How long a reading stays on the tile.
    public static let displayInterval: TimeInterval = 30 * 60
    /// The observer rewrites its state at least every 5 minutes; older state means it is not running.
    public static let observerQuietInterval: TimeInterval = 15 * 60

    public init(
        source: String?,
        collector: String,
        generatedAt: Date,
        readAt: Date,
        working: Int,
        waiting: Int,
        idle: Int,
        activeHarnesses: [String] = []
    ) {
        self.source = source
        self.collector = collector
        self.generatedAt = generatedAt
        self.readAt = readAt
        self.working = working
        self.waiting = waiting
        self.idle = idle
        self.activeHarnesses = activeHarnesses
    }

    /// Where a host shares its summary with `tailscale serve --set-path`.
    public static let summaryPath = "/fleet/agent-summary.json"

    /// The summary's address on a host that shares it; nil without a MagicDNS name.
    public static func summaryURL(for host: TailnetHost) -> URL? {
        guard let dnsName = host.magicDNSName, !dnsName.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = dnsName
        components.path = summaryPath
        return components.url
    }

    /// Readings from the same place replace each other.
    public var sourceKey: String {
        source?.lowercased() ?? "this-mac"
    }

    public var hidesAt: Date {
        readAt.addingTimeInterval(Self.displayInterval)
    }

    public func isShown(at date: Date) -> Bool {
        date < hidesAt
    }

    public var isObserverQuiet: Bool {
        readAt.timeIntervalSince(generatedAt) > Self.observerQuietInterval
    }

    /// One short line for the tile, e.g. "Claw · 1 working" or "2 working · 1 needs you".
    public var summaryText: String {
        if isObserverQuiet {
            return "Agent observer quiet"
        }
        var parts: [String] = []
        if activeHarnesses.count == 1, let harness = activeHarnesses.first {
            parts.append(Self.harnessName(harness))
        }
        if working > 0 {
            parts.append("\(working) working")
        }
        if waiting > 0 {
            parts.append(waiting == 1 ? "1 needs you" : "\(waiting) need you")
        }
        if working == 0 && waiting == 0 {
            return "No agents working"
        }
        return parts.joined(separator: " · ")
    }

    public static func harnessName(_ harness: String) -> String {
        switch harness {
        case "claude-code":
            return "Claude"
        case "codex":
            return "Codex"
        case "openclaw":
            return "Claw"
        default:
            return harness
        }
    }

    /// A local reading belongs to this Mac's tile; a remote one to the host it was read
    /// from or that the observer names.
    public func matches(_ host: TailnetHost) -> Bool {
        guard let source else {
            return host.role == .thisDevice
        }
        let hostName = host.name.lowercased()
        let dnsName = host.magicDNSName?.lowercased()
        return [source.lowercased(), collector.lowercased()].contains { name in
            hostName == name || dnsName == name || dnsName?.hasPrefix(name + ".") == true
        }
    }
}

public enum TailnetAgentActivityError: LocalizedError, Equatable {
    case notAgentState

    public var errorDescription: String? {
        "The host did not return a Fleet agent observer state document."
    }
}

/// Reads the observer's counts-only `fleet.agent-summary/1` file, or the counts out of its
/// full `fleet.agent-state/1` document (per-agent usage, models and session ids are ignored,
/// so they never reach the shared snapshot).
public struct TailnetAgentActivityParser: Sendable {
    public static let summarySchema = "fleet.agent-summary/1"
    public static let stateSchema = "fleet.agent-state/1"

    public init() {}

    public func parse(_ data: Data, source: String?, readAt: Date) throws -> TailnetAgentActivity {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard [Self.summarySchema, Self.stateSchema].contains(document.schema),
              let generatedAt = Self.parseDate(document.generatedAt)
        else {
            throw TailnetAgentActivityError.notAgentState
        }
        let active = Set(
            document.activeHarnesses ?? (document.agents ?? [])
                .filter { $0.status == "working" || $0.status == "waiting" }
                .map(\.harness)
        )
        return TailnetAgentActivity(
            source: source,
            collector: document.host ?? source ?? "this Mac",
            generatedAt: generatedAt,
            readAt: readAt,
            working: document.summary.working ?? 0,
            waiting: document.summary.waiting ?? 0,
            idle: document.summary.idle ?? 0,
            activeHarnesses: active.sorted()
        )
    }

    /// The observer writes Python ISO timestamps such as `2026-11-14T20:02:20+00:00`.
    private static func parseDate(_ value: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: value) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }

    private struct Document: Decodable {
        struct Summary: Decodable {
            let working: Int?
            let waiting: Int?
            let idle: Int?
        }

        struct Agent: Decodable {
            let harness: String
            let status: String
        }

        let schema: String
        let host: String?
        let generatedAt: String
        let summary: Summary
        /// Summary documents name the busy harnesses directly.
        let activeHarnesses: [String]?
        /// State documents list every agent instead.
        let agents: [Agent]?
    }
}
