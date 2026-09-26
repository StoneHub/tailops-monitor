import Foundation

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
