import Foundation
import Security
import TailOpsCore

public protocol SharedSnapshotStoring {
    func load() throws -> TailnetSnapshot?
    func save(_ snapshot: TailnetSnapshot) throws
    func loadActionConfiguration() throws -> TailnetActionConfiguration?
    func saveActionConfiguration(_ configuration: TailnetActionConfiguration) throws
}

public struct SharedSnapshotStore: SharedSnapshotStoring {
    public static let appGroupIdentifier = "group.dev.tailops.monitor"
    private let fileManager: FileManager
    private let baseURLOverride: [URL]?

    public init(fileManager: FileManager = .default, baseURLs: [URL]? = nil) {
        self.fileManager = fileManager
        self.baseURLOverride = baseURLs
    }

    public func load() throws -> TailnetSnapshot? {
        try loadFirstExisting(path: "tailops-snapshot.json", as: TailnetSnapshot.self)
    }

    public func save(_ snapshot: TailnetSnapshot) throws {
        let data = try JSONEncoder.tailops.encode(snapshot)
        try write(data, path: "tailops-snapshot.json")
    }

    public func loadActionConfiguration() throws -> TailnetActionConfiguration? {
        try loadFirstExisting(path: "tailops-actions.json", as: TailnetActionConfiguration.self)
    }

    public func saveActionConfiguration(_ configuration: TailnetActionConfiguration) throws {
        let data = try JSONEncoder.tailops.encode(configuration)
        try write(data, path: "tailops-actions.json")
    }

    private func loadFirstExisting<T: Decodable>(path: String, as type: T.Type) throws -> T? {
        for baseURL in try baseURLs() {
            let url = baseURL.appending(path: path)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let data = try Data(contentsOf: url)
            return try JSONDecoder.tailops.decode(T.self, from: data)
        }
        return nil
    }

    private func write(_ data: Data, path: String) throws {
        var firstError: Error?
        var didWrite = false

        for baseURL in try baseURLs() {
            let url = baseURL.appending(path: path)
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
                didWrite = true
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if !didWrite, let firstError {
            throw firstError
        }
    }

    private func baseURLs() throws -> [URL] {
        if let baseURLOverride {
            return baseURLOverride
        }

        let appGroupURLs = Self.appGroupIdentifierCandidates.reduce(into: [URL?]()) { urls, identifier in
            urls.append(fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier))
            urls.append(explicitAppGroupURL(identifier: identifier))
        }

        return (appGroupURLs + [Optional(fallbackApplicationSupportURL())])
            .compactMap(\.self)
            .deduplicatedByPath()
    }

    private func explicitAppGroupURL(identifier: String) -> URL? {
        guard let home = fileManager.homeDirectoryForCurrentUser.path.removingPercentEncoding else {
            return nil
        }

        return URL(fileURLWithPath: home)
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Group Containers", directoryHint: .isDirectory)
            .appending(path: identifier, directoryHint: .isDirectory)
    }

    private func fallbackApplicationSupportURL() -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appending(path: "TailOpsMac", directoryHint: .isDirectory)
    }
}

private extension SharedSnapshotStore {
    static var appGroupIdentifierCandidates: [String] {
        (signedAppGroupIdentifiers() + [teamPrefixedAppGroupIdentifier(), appGroupIdentifier])
            .compactMap(\.self)
            .deduplicated()
    }

    static func signedAppGroupIdentifiers() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let identifiers = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil
              )
        else {
            return []
        }

        if let identifiers = identifiers as? [String] {
            return identifiers
        }

        if let identifier = identifiers as? String {
            return [identifier]
        }

        return []
    }

    static func teamPrefixedAppGroupIdentifier() -> String? {
        guard let task = SecTaskCreateFromSelf(nil),
              let applicationIdentifier = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.application-identifier" as CFString,
                nil
              ) as? String,
              let teamIdentifier = applicationIdentifier.split(separator: ".").first
        else {
            return nil
        }

        return "\(teamIdentifier).\(appGroupIdentifier)"
    }
}

private extension Array where Element == URL {
    func deduplicatedByPath() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}

private extension Array where Element == String {
    func deduplicated() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

extension JSONEncoder {
    static var tailops: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var tailops: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
