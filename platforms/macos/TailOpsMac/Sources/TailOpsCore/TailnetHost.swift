import Foundation

public struct TailnetHost: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Equatable, Sendable {
        case thisDevice
        case peer
    }

    public enum Status: String, Codable, Equatable, Sendable {
        case online
        case warning
        case offline
    }

    public let id: String
    public let name: String
    public let role: Role
    public let status: Status
    public let operatingSystem: String?
    public let primaryAddress: String?
    public let magicDNSName: String?
    public let lastSeen: Date?
    public let services: [TailnetService]
    public let diagnostics: TailnetHostDiagnostics?
    /// How this Mac currently reaches an online peer; nil for this device and offline hosts.
    public let connection: TailnetConnection?
    public let keyExpiry: Date?

    /// Online hosts whose node key expires within this window show as warnings.
    public static let keyExpiryWarningInterval: TimeInterval = 7 * 24 * 60 * 60

    public init(
        id: String,
        name: String,
        role: Role,
        status: Status,
        operatingSystem: String?,
        primaryAddress: String?,
        magicDNSName: String?,
        lastSeen: Date?,
        services: [TailnetService],
        diagnostics: TailnetHostDiagnostics? = nil,
        connection: TailnetConnection? = nil,
        keyExpiry: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.status = status
        self.operatingSystem = operatingSystem
        self.primaryAddress = primaryAddress
        self.magicDNSName = magicDNSName
        self.lastSeen = lastSeen
        self.services = services
        self.diagnostics = diagnostics
        self.connection = connection
        self.keyExpiry = keyExpiry
    }

    public func withDiagnostics(_ diagnostics: TailnetHostDiagnostics?) -> TailnetHost {
        TailnetHost(
            id: id,
            name: name,
            role: role,
            status: status,
            operatingSystem: operatingSystem,
            primaryAddress: primaryAddress,
            magicDNSName: magicDNSName,
            lastSeen: lastSeen,
            services: services,
            diagnostics: diagnostics,
            connection: connection,
            keyExpiry: keyExpiry
        )
    }
}

public enum TailnetConnection: Codable, Equatable, Sendable {
    case direct
    case derp(region: String)
    case peerRelay
    /// Online, but no WireGuard session is active right now; Tailscale connects on demand.
    case idle

    public var label: String {
        switch self {
        case .direct:
            return "Direct"
        case .derp(let region):
            return "DERP \(region)"
        case .peerRelay:
            return "Peer relay"
        case .idle:
            return "Idle"
        }
    }
}

public struct TailnetService: Codable, Equatable, Sendable {
    public let label: String
    public let url: URL

    public init(label: String, url: URL) {
        self.label = label
        self.url = url
    }
}

public struct TailnetHostDiagnostics: Codable, Equatable, Sendable {
    public let ping: TailnetPingSummary?

    public init(ping: TailnetPingSummary? = nil) {
        self.ping = ping
    }
}

public struct TailnetSnapshot: Codable, Equatable, Sendable {
    public let hosts: [TailnetHost]
    public let generatedAt: Date
    /// Tailnet-wide state from the same status read; nil for snapshots saved by older builds.
    public let health: TailnetHealth?

    public init(hosts: [TailnetHost], generatedAt: Date = Date(), health: TailnetHealth? = nil) {
        self.hosts = hosts
        self.generatedAt = generatedAt
        self.health = health
    }

    public func withHosts(_ hosts: [TailnetHost]) -> TailnetSnapshot {
        TailnetSnapshot(hosts: hosts, generatedAt: generatedAt, health: health)
    }
}

public struct TailnetHealth: Codable, Equatable, Sendable {
    /// Tailscale's backend state, such as `Running`, `Stopped`, or `NeedsLogin`.
    public let backendState: String
    public let warnings: [String]
    public let exitNode: TailnetExitNode?
    public let tailnetName: String?

    public init(
        backendState: String,
        warnings: [String] = [],
        exitNode: TailnetExitNode? = nil,
        tailnetName: String? = nil
    ) {
        self.backendState = backendState
        self.warnings = warnings
        self.exitNode = exitNode
        self.tailnetName = tailnetName
    }

    public var isRunning: Bool {
        backendState == "Running"
    }

    /// A short sentence for a non-running backend, or nil while running.
    public var backendProblem: String? {
        switch backendState {
        case "Running":
            return nil
        case "Stopped":
            return "Tailscale is turned off"
        case "NeedsLogin":
            return "Tailscale needs you to log in"
        case "NeedsMachineAuth":
            return "This Mac is waiting for admin approval"
        case "Starting", "NoState":
            return "Tailscale is starting"
        default:
            return "Tailscale is \(backendState)"
        }
    }
}

public struct TailnetExitNode: Codable, Equatable, Sendable {
    public let name: String
    /// For location-aware exit nodes such as Mullvad, e.g. "Miami, FL".
    public let location: String?

    public init(name: String, location: String? = nil) {
        self.name = name
        self.location = location
    }

    public var displayName: String {
        location ?? name
    }
}

public struct TailnetWidgetHostLayout: Equatable, Sendable {
    public let visibleHosts: [TailnetHost]
    public let hiddenOfflineCount: Int

    public init(hosts: [TailnetHost], limit: Int) {
        let safeLimit = max(limit, 0)
        let reachable = hosts
            .filter { $0.status != .offline }
            .sorted { Self.reachableRank(for: $0) < Self.reachableRank(for: $1) }
        let offline = hosts.filter { $0.status == .offline }

        if reachable.isEmpty {
            visibleHosts = Array(offline.prefix(safeLimit))
        } else {
            visibleHosts = Array(reachable.prefix(safeLimit))
        }

        let visibleOfflineCount = visibleHosts.filter { $0.status == .offline }.count
        hiddenOfflineCount = max(offline.count - visibleOfflineCount, 0)
    }

    private static func reachableRank(for host: TailnetHost) -> Int {
        switch (host.role, host.status) {
        case (.peer, .online):
            return 0
        case (.peer, .warning):
            return 1
        case (.thisDevice, .online):
            return 2
        case (.thisDevice, .warning):
            return 3
        case (_, .offline):
            return 4
        }
    }
}
