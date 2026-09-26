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
        diagnostics: TailnetHostDiagnostics? = nil
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
            diagnostics: diagnostics
        )
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

    public init(hosts: [TailnetHost], generatedAt: Date = Date()) {
        self.hosts = hosts
        self.generatedAt = generatedAt
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
