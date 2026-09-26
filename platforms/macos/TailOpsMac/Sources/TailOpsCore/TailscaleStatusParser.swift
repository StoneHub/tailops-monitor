import Foundation

public enum TailnetPeerSelectionPolicy: Sendable {
    case managedFleet
    case allPeers

    fileprivate func includes(_ node: TailscaleNode) -> Bool {
        switch self {
        case .managedFleet:
            return !node.tags.contains("tag:mullvad-exit-node")
        case .allPeers:
            return true
        }
    }
}

public struct TailnetSnapshotParser: Sendable {
    private let peerSelectionPolicy: TailnetPeerSelectionPolicy

    public init(peerSelectionPolicy: TailnetPeerSelectionPolicy = .managedFleet) {
        self.peerSelectionPolicy = peerSelectionPolicy
    }

    public func parse(_ data: Data, generatedAt: Date = Date()) throws -> TailnetSnapshot {
        let response = try JSONDecoder().decode(TailscaleStatusResponse.self, from: data)
        var hosts: [TailnetHost] = []

        if let selfDevice = response.selfDevice {
            hosts.append(Self.host(from: selfDevice, role: .thisDevice, at: generatedAt))
        }

        hosts.append(contentsOf: response.peers
            .filter { peerSelectionPolicy.includes($0.value) }
            .sorted { $0.key < $1.key }
            .map { Self.host(from: $0.value, role: .peer, at: generatedAt) })

        return TailnetSnapshot(
            hosts: Self.sortedByRecentAvailability(hosts),
            generatedAt: generatedAt,
            health: Self.health(from: response)
        )
    }

    /// Exit nodes are found among all peers, because provider nodes such as
    /// Mullvad are hidden from the managed-fleet host list.
    private static func health(from response: TailscaleStatusResponse) -> TailnetHealth? {
        guard let backendState = response.backendState, !backendState.isEmpty else { return nil }
        let exitNode = response.peers.values.first { $0.exitNode == true }.map { node in
            TailnetExitNode(
                name: TailnetDisplayName.cleaned(node.hostName) ?? normalizedDNSName(node.dnsName) ?? "Exit node",
                location: node.location?.displayName
            )
        }
        return TailnetHealth(
            backendState: backendState,
            warnings: response.health.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            exitNode: exitNode,
            tailnetName: response.currentTailnetName
        )
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

    private static func host(from node: TailscaleNode, role: TailnetHost.Role, at date: Date) -> TailnetHost {
        let magicDNSName = normalizedDNSName(node.dnsName)
        let isOnline = node.online == true
        let keyExpiry = node.keyExpiry.flatMap(parseDate)
        let keyExpiresSoon = keyExpiry.map {
            $0.timeIntervalSince(date) < TailnetHost.keyExpiryWarningInterval
        } ?? false

        return TailnetHost(
            id: node.id ?? node.publicKey ?? node.dnsName ?? node.hostName ?? UUID().uuidString,
            name: TailnetDisplayName.cleaned(node.hostName) ?? magicDNSName ?? "Unknown host",
            role: role,
            status: isOnline ? (keyExpiresSoon ? .warning : .online) : .offline,
            operatingSystem: node.os,
            primaryAddress: node.tailscaleIPs?.first,
            magicDNSName: magicDNSName,
            lastSeen: node.lastSeen.flatMap(parseDate),
            services: [],
            connection: role == .peer && isOnline ? connection(for: node) : nil,
            keyExpiry: keyExpiry
        )
    }

    /// Mirrors how `tailscale status` describes a peer: a current UDP address
    /// means a direct path, otherwise traffic goes through a peer relay or DERP.
    private static func connection(for node: TailscaleNode) -> TailnetConnection {
        if let address = node.currentAddress, !address.isEmpty {
            return .direct
        }
        if let peerRelay = node.peerRelay, !peerRelay.isEmpty {
            return .peerRelay
        }
        if node.active == true, let relay = node.relay, !relay.isEmpty {
            return .derp(region: relay)
        }
        return .idle
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

enum TailnetDisplayName {
    static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmingTailscaleDuplicateSuffix(from: trimmed)
    }

    private static func trimmingTailscaleDuplicateSuffix(from value: String) -> String {
        guard value.hasSuffix(")") else { return value }
        let closeParenthesis = value.index(before: value.endIndex)
        guard let openParenthesis = value[..<closeParenthesis].lastIndex(of: "(") else {
            return value
        }

        let prefix = value[..<openParenthesis]
        guard prefix.hasSuffix(" ") else { return value }

        let suffixStart = value.index(after: openParenthesis)
        let suffix = value[suffixStart..<closeParenthesis]
        guard !suffix.isEmpty,
              suffix.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) })
        else {
            return value
        }

        return prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TailscaleStatusResponse: Decodable {
    let selfDevice: TailscaleNode?
    let peers: [String: TailscaleNode]
    let backendState: String?
    let health: [String]
    let currentTailnetName: String?

    enum CodingKeys: String, CodingKey {
        case selfDevice = "Self"
        case peers = "Peer"
        case backendState = "BackendState"
        case health = "Health"
        case currentTailnet = "CurrentTailnet"
    }

    private struct CurrentTailnet: Decodable {
        let name: String?

        enum CodingKeys: String, CodingKey {
            case name = "Name"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selfDevice = try container.decodeIfPresent(TailscaleNode.self, forKey: .selfDevice)
        peers = try container.decodeIfPresent([String: TailscaleNode].self, forKey: .peers) ?? [:]
        backendState = try container.decodeIfPresent(String.self, forKey: .backendState)
        health = try container.decodeIfPresent([String].self, forKey: .health) ?? []
        currentTailnetName = try container.decodeIfPresent(CurrentTailnet.self, forKey: .currentTailnet)?.name
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
    let tags: [String]
    let currentAddress: String?
    let relay: String?
    let peerRelay: String?
    let active: Bool?
    let exitNode: Bool?
    let keyExpiry: String?
    let location: TailscaleLocation?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case publicKey = "PublicKey"
        case hostName = "HostName"
        case dnsName = "DNSName"
        case tailscaleIPs = "TailscaleIPs"
        case online = "Online"
        case lastSeen = "LastSeen"
        case os = "OS"
        case tags = "Tags"
        case currentAddress = "CurAddr"
        case relay = "Relay"
        case peerRelay = "PeerRelay"
        case active = "Active"
        case exitNode = "ExitNode"
        case keyExpiry = "KeyExpiry"
        case location = "Location"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        publicKey = try container.decodeIfPresent(String.self, forKey: .publicKey)
        hostName = try container.decodeIfPresent(String.self, forKey: .hostName)
        dnsName = try container.decodeIfPresent(String.self, forKey: .dnsName)
        tailscaleIPs = try container.decodeIfPresent([String].self, forKey: .tailscaleIPs)
        online = try container.decodeIfPresent(Bool.self, forKey: .online)
        lastSeen = try container.decodeIfPresent(String.self, forKey: .lastSeen)
        os = try container.decodeIfPresent(String.self, forKey: .os)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        currentAddress = try container.decodeIfPresent(String.self, forKey: .currentAddress)
        relay = try container.decodeIfPresent(String.self, forKey: .relay)
        peerRelay = try container.decodeIfPresent(String.self, forKey: .peerRelay)
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
        exitNode = try container.decodeIfPresent(Bool.self, forKey: .exitNode)
        keyExpiry = try container.decodeIfPresent(String.self, forKey: .keyExpiry)
        location = try container.decodeIfPresent(TailscaleLocation.self, forKey: .location)
    }
}

private struct TailscaleLocation: Decodable {
    let city: String?
    let country: String?

    enum CodingKeys: String, CodingKey {
        case city = "City"
        case country = "Country"
    }

    var displayName: String? {
        [city, country].compactMap { $0 }.first { !$0.isEmpty && $0 != "Any" }
    }
}
