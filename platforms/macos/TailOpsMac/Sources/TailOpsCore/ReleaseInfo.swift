import Foundation

/// Where TailOps releases live and what a release must contain.
public enum TailOpsRelease {
    /// The releases list, not /releases/latest: development-signed builds publish as
    /// pre-releases, which the latest endpoint hides.
    public static let listURL = URL(string: "https://api.github.com/repos/StoneHub/tailops-monitor/releases?per_page=20")!
    /// Releases are signed by the owner's team; an update must match the running app's team.
    public static let officialTeamIdentifier = "N6GPP46885"

    public static func assetName(for version: SemanticVersion) -> String {
        "TailOps-\(version).zip"
    }
}

/// The parts of a GitHub release the updater needs; decoded from the releases endpoint.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: SemanticVersion
    public let tag: String
    public let pageURL: URL
    public let notes: String
    public let downloadURL: URL
    public let assetSize: Int64

    public var firstNoteLine: String {
        notes.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
    }

    public enum ParseError: Error, Equatable, LocalizedError {
        case badTag(String)
        case noAsset(String)
        case badJSON
        case noRelease

        public var errorDescription: String? {
            switch self {
            case .badTag(let tag):
                return "Release tag \(tag) is not a version."
            case .noAsset(let name):
                return "Release has no asset named \(name)."
            case .badJSON:
                return "The release list could not be read."
            case .noRelease:
                return "No published release carries a TailOps download yet."
            }
        }
    }

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            let size: Int64

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size
            }
        }

        let tagName: String
        let htmlURL: URL
        let body: String?
        let assets: [Asset]
        let draft: Bool?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case assets
            case draft
        }
    }

    /// The highest version among published releases, pre-releases included, that
    /// carries the expected asset.
    public static func newest(
        from data: Data,
        assetNamed: (SemanticVersion) -> String = TailOpsRelease.assetName(for:)
    ) throws -> ReleaseInfo {
        guard let payloads = try? JSONDecoder().decode([Payload].self, from: data) else {
            throw ParseError.badJSON
        }
        let releases = payloads
            .filter { $0.draft != true }
            .compactMap { try? make($0, assetNamed: assetNamed) }
        guard let newest = releases.max(by: { $0.version < $1.version }) else {
            throw ParseError.noRelease
        }
        return newest
    }

    private static func make(_ payload: Payload, assetNamed: (SemanticVersion) -> String) throws -> ReleaseInfo {
        guard let version = SemanticVersion.parse(payload.tagName) else {
            throw ParseError.badTag(payload.tagName)
        }
        let wanted = assetNamed(version)
        guard let asset = payload.assets.first(where: { $0.name == wanted }) else {
            throw ParseError.noAsset(wanted)
        }
        return ReleaseInfo(
            version: version,
            tag: payload.tagName,
            pageURL: payload.htmlURL,
            notes: payload.body ?? "",
            downloadURL: asset.browserDownloadURL,
            assetSize: asset.size
        )
    }
}

/// A dotted numeric version such as 1.1.10, compared component by component.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init(_ components: [Int]) {
        self.components = components
    }

    /// Accepts "1.2.3" or "v1.2.3"; anything with a non-numeric part is nil.
    public static func parse(_ text: String) -> SemanticVersion? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("v") || body.hasPrefix("V") {
            body.removeFirst()
        }
        guard !body.isEmpty else { return nil }

        var parts: [Int] = []
        for piece in body.split(separator: ".", omittingEmptySubsequences: false) {
            guard let number = Int(piece), number >= 0 else { return nil }
            parts.append(number)
        }
        return SemanticVersion(parts)
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    /// 1.2 and 1.2.0 are the same version.
    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public func hash(into hasher: inout Hasher) {
        var trimmed = components
        while trimmed.last == 0 {
            trimmed.removeLast()
        }
        hasher.combine(trimmed)
    }
}
