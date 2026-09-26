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
            hosts.append(Self.host(from: selfDevice, role: .thisDevice))
        }

        hosts.append(contentsOf: response.peers
            .filter { peerSelectionPolicy.includes($0.value) }
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
        let magicDNSName = normalizedDNSName(node.dnsName)
        return TailnetHost(
            id: node.id ?? node.publicKey ?? node.dnsName ?? node.hostName ?? UUID().uuidString,
            name: TailnetDisplayName.cleaned(node.hostName) ?? magicDNSName ?? "Unknown host",
            role: role,
            status: node.online == true ? .online : .offline,
            operatingSystem: node.os,
            primaryAddress: node.tailscaleIPs?.first,
            magicDNSName: magicDNSName,
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
    let tags: [String]

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
    }
}
