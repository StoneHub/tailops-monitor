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

public struct TaildropTarget: Codable, Equatable, Identifiable, Sendable {
    public let address: String
    public let name: String
    public let detail: String?
    public let isAvailable: Bool

    public var id: String {
        address
    }

    public init(address: String, name: String, detail: String? = nil, isAvailable: Bool = true) {
        self.address = address
        self.name = name
        self.detail = detail
        self.isAvailable = isAvailable
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

public struct TailOpsAppPreferences: Codable, Equatable, Sendable {
    public let launchAtLogin: Bool
    public let showMenuBarIcon: Bool
    public let opensSettingsFromWidget: Bool

    public init(
        launchAtLogin: Bool = false,
        showMenuBarIcon: Bool = true,
        opensSettingsFromWidget: Bool = true
    ) {
        self.launchAtLogin = launchAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.opensSettingsFromWidget = opensSettingsFromWidget
    }
}

public struct TailOpsSettingsOpenRequest: Codable, Equatable, Sendable {
    public let requestedAt: Date

    public init(requestedAt: Date = Date()) {
        self.requestedAt = requestedAt
    }
}

public enum TailOpsSettingsOpenSignal {
    public static let notificationName = "dev.tailops.monitor.openSettings"
    public static let url = URL(string: "tailops://settings")!
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

public struct TaildropTargetsParser: Sendable {
    public init() {}

    public func parse(_ output: String) -> [TaildropTarget] {
        output
            .split(separator: "\n")
            .compactMap { Self.parseLine(String($0)) }
    }

    private static func parseLine(_ line: String) -> TaildropTarget? {
        let fields = line
            .split(separator: "\t", omittingEmptySubsequences: false)
            .map(String.init)

        guard fields.count >= 2 else { return nil }
        let detail = fields.count >= 3 && !fields[2].isEmpty ? fields[2] : nil
        return TaildropTarget(
            address: fields[0],
            name: fields[1],
            detail: detail,
            isAvailable: !(detail?.localizedCaseInsensitiveContains("offline") ?? false)
        )
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

public struct TailnetSummary: Equatable, Sendable {
    public enum TrafficLight: String, Codable, Equatable, Sendable {
        case healthy
        case warning
        case offline
    }

    public let hosts: [TailnetHost]

    public init(hosts: [TailnetHost]) {
        self.hosts = hosts
    }

    public var onlineCount: Int {
        hosts.filter { $0.status == .online }.count
    }

    public var warningCount: Int {
        hosts.filter { $0.status == .warning }.count
    }

    public var offlineCount: Int {
        hosts.filter { $0.status == .offline }.count
    }

    public var trafficLight: TrafficLight {
        if warningCount > 0 { return .warning }
        if offlineCount > 0 { return .offline }
        return .healthy
    }
}

public struct HostAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case ssh
        case dashboard
        case copyAddress
    }

    public let emoji: String?
    public let title: String
    public let kind: Kind
    public let url: URL?
    public let value: String?

    public init(emoji: String? = nil, title: String, kind: Kind, url: URL?, value: String?) {
        self.emoji = emoji
        self.title = title
        self.kind = kind
        self.url = url
        self.value = value
    }
}

public struct TailnetQuickAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case ssh
        case url
        case copy
    }

    public let emoji: String
    public let title: String
    public let kind: Kind
    public let target: String

    public init(emoji: String, title: String, kind: Kind, target: String) {
        self.emoji = emoji
        self.title = title
        self.kind = kind
        self.target = target
    }
}

public struct TailnetHostActionConfiguration: Codable, Equatable, Sendable {
    public let hostID: String
    public let actions: [TailnetQuickAction]

    public init(hostID: String, actions: [TailnetQuickAction]) {
        self.hostID = hostID
        self.actions = actions
    }
}

public struct TailnetActionConfiguration: Codable, Equatable, Sendable {
    public let hostActions: [TailnetHostActionConfiguration]

    public init(hostActions: [TailnetHostActionConfiguration] = []) {
        self.hostActions = hostActions
    }

    public func actions(for host: TailnetHost) -> [TailnetQuickAction] {
        let identifiers = Set([
            host.id,
            host.name,
            host.magicDNSName,
            host.primaryAddress,
        ].compactMap { $0 })

        return hostActions.first { identifiers.contains($0.hostID) }?.actions ?? []
    }

    public func validationIssues() -> [TailnetActionValidationIssue] {
        var issues: [TailnetActionValidationIssue] = []

        for (hostIndex, host) in hostActions.enumerated() {
            if host.hostID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.emptyHostID(hostIndex: hostIndex))
            }

            for (actionIndex, action) in host.actions.enumerated() {
                if action.emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(.emptyEmoji(hostIndex: hostIndex, actionIndex: actionIndex))
                }
                if action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(.emptyTitle(hostIndex: hostIndex, actionIndex: actionIndex))
                }
                let target = action.target.trimmingCharacters(in: .whitespacesAndNewlines)
                if target.isEmpty {
                    issues.append(.emptyTarget(hostIndex: hostIndex, actionIndex: actionIndex))
                    continue
                }

                switch action.kind {
                case .url:
                    if URL(string: target)?.scheme == nil {
                        issues.append(.invalidURL(hostIndex: hostIndex, actionIndex: actionIndex))
                    }
                case .ssh:
                    if target.localizedCaseInsensitiveContains("://") {
                        issues.append(.sshTargetContainsScheme(hostIndex: hostIndex, actionIndex: actionIndex))
                    }
                case .copy:
                    break
                }
            }
        }

        return issues
    }
}

public enum TailnetActionValidationIssue: Codable, Equatable, Sendable {
    case emptyHostID(hostIndex: Int)
    case emptyEmoji(hostIndex: Int, actionIndex: Int)
    case emptyTitle(hostIndex: Int, actionIndex: Int)
    case emptyTarget(hostIndex: Int, actionIndex: Int)
    case invalidURL(hostIndex: Int, actionIndex: Int)
    case sshTargetContainsScheme(hostIndex: Int, actionIndex: Int)

    public var message: String {
        switch self {
        case .emptyHostID(let hostIndex):
            return "Host \(hostIndex + 1): add a host name, MagicDNS name, Tailscale IP, or host ID."
        case .emptyEmoji(let hostIndex, let actionIndex):
            return "Host \(hostIndex + 1), action \(actionIndex + 1): add an emoji."
        case .emptyTitle(let hostIndex, let actionIndex):
            return "Host \(hostIndex + 1), action \(actionIndex + 1): add a title."
        case .emptyTarget(let hostIndex, let actionIndex):
            return "Host \(hostIndex + 1), action \(actionIndex + 1): add a target."
        case .invalidURL(let hostIndex, let actionIndex):
            return "Host \(hostIndex + 1), action \(actionIndex + 1): URL actions need http:// or https://."
        case .sshTargetContainsScheme(let hostIndex, let actionIndex):
            return "Host \(hostIndex + 1), action \(actionIndex + 1): SSH targets should be host names, not ssh:// URLs."
        }
    }
}

public struct HostActionCatalog: Sendable {
    private let configuration: TailnetActionConfiguration

    public init(configuration: TailnetActionConfiguration = TailnetActionConfiguration()) {
        self.configuration = configuration
    }

    public func actions(for host: TailnetHost) -> [HostAction] {
        let configuredActions = configuration.actions(for: host).compactMap(Self.hostAction)
        let defaultActions = Self.defaultActions(for: host)
        return configuredActions + defaultActions.filter { defaultAction in
            !configuredActions.contains { configuredAction in
                Self.matchesSameTarget(configuredAction, defaultAction)
            }
        }
    }

    private static func defaultActions(for host: TailnetHost) -> [HostAction] {
        var actions: [HostAction] = []
        let connectionName = host.magicDNSName ?? host.primaryAddress

        if let connectionName, let sshURL = URL(string: "ssh://\(connectionName)") {
            actions.append(HostAction(title: "SSH", kind: .ssh, url: sshURL, value: connectionName))
        }

        actions.append(contentsOf: host.services.map { service in
            HostAction(title: service.label, kind: .dashboard, url: service.url, value: nil)
        })

        if let primaryAddress = host.primaryAddress {
            actions.append(HostAction(title: "Copy IP", kind: .copyAddress, url: nil, value: primaryAddress))
        }

        return actions
    }

    private static func hostAction(from quickAction: TailnetQuickAction) -> HostAction? {
        switch quickAction.kind {
        case .ssh:
            guard let url = URL(string: "ssh://\(quickAction.target)") else { return nil }
            return HostAction(emoji: quickAction.emoji, title: quickAction.title, kind: .ssh, url: url, value: quickAction.target)
        case .url:
            guard let url = URL(string: quickAction.target) else { return nil }
            return HostAction(emoji: quickAction.emoji, title: quickAction.title, kind: .dashboard, url: url, value: nil)
        case .copy:
            return HostAction(emoji: quickAction.emoji, title: quickAction.title, kind: .copyAddress, url: nil, value: quickAction.target)
        }
    }

    private static func matchesSameTarget(_ lhs: HostAction, _ rhs: HostAction) -> Bool {
        lhs.kind == rhs.kind && lhs.url == rhs.url && lhs.value == rhs.value
    }
}

public struct TailnetSnapshotParser: Sendable {
    public init() {}

    public func parse(_ data: Data, generatedAt: Date = Date()) throws -> TailnetSnapshot {
        let response = try JSONDecoder().decode(TailscaleStatusResponse.self, from: data)
        var hosts: [TailnetHost] = []

        if let selfDevice = response.selfDevice {
            hosts.append(Self.host(from: selfDevice, role: .thisDevice))
        }

        hosts.append(contentsOf: response.peers
            .sorted { $0.key < $1.key }
            .map { Self.host(from: $0.value, role: .peer) })

        return TailnetSnapshot(hosts: Self.sortedByRecentAvailability(hosts), generatedAt: generatedAt)
    }

    private static func sortedByRecentAvailability(_ hosts: [TailnetHost]) -> [TailnetHost] {
        hosts.sorted { left, right in
            let leftRank = availabilityRank(left)
            let rightRank = availabilityRank(right)

            if leftRank != rightRank {
                return leftRank < rightRank
            }

            if left.role != right.role {
                return left.role == .thisDevice
            }

            switch (left.lastSeen, right.lastSeen) {
            case (.some(let leftDate), .some(let rightDate)) where leftDate != rightDate:
                return leftDate > rightDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
        }
    }

    private static func availabilityRank(_ host: TailnetHost) -> Int {
        switch host.status {
        case .online:
            return 0
        case .warning:
            return 1
        case .offline:
            return 2
        }
    }

    private static func host(from node: TailscaleNode, role: TailnetHost.Role) -> TailnetHost {
        TailnetHost(
            id: node.id ?? node.publicKey ?? node.dnsName ?? node.hostName ?? UUID().uuidString,
            name: node.hostName ?? normalizedDNSName(node.dnsName) ?? "Unknown host",
            role: role,
            status: node.online == true ? .online : .offline,
            operatingSystem: node.os,
            primaryAddress: node.tailscaleIPs?.first,
            magicDNSName: normalizedDNSName(node.dnsName),
            lastSeen: node.lastSeen.flatMap(parseDate),
            services: []
        )
    }

    private static func normalizedDNSName(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.hasSuffix(".") ? String(value.dropLast()) : value
    }

    private static func parseDate(_ value: String) -> Date? {
        let internetDateTime = ISO8601DateFormatter()
        internetDateTime.formatOptions = [.withInternetDateTime]
        if let date = internetDateTime.date(from: value) {
            return date
        }

        let fractionalSeconds = ISO8601DateFormatter()
        fractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalSeconds.date(from: value)
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

private struct TailscaleStatusResponse: Decodable {
    let selfDevice: TailscaleNode?
    let peers: [String: TailscaleNode]

    enum CodingKeys: String, CodingKey {
        case selfDevice = "Self"
        case peers = "Peer"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selfDevice = try container.decodeIfPresent(TailscaleNode.self, forKey: .selfDevice)
        peers = try container.decodeIfPresent([String: TailscaleNode].self, forKey: .peers) ?? [:]
    }
}

private struct TailscaleNode: Decodable {
    let id: String?
    let publicKey: String?
    let hostName: String?
    let dnsName: String?
    let tailscaleIPs: [String]?
    let online: Bool?
    let lastSeen: String?
    let os: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case publicKey = "PublicKey"
        case hostName = "HostName"
        case dnsName = "DNSName"
        case tailscaleIPs = "TailscaleIPs"
        case online = "Online"
        case lastSeen = "LastSeen"
        case os = "OS"
    }
}
