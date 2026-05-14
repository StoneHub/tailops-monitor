import Foundation
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

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load() throws -> TailnetSnapshot? {
        let url = try snapshotURL()
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.tailops.decode(TailnetSnapshot.self, from: data)
    }

    public func save(_ snapshot: TailnetSnapshot) throws {
        let url = try snapshotURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.tailops.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    public func loadActionConfiguration() throws -> TailnetActionConfiguration? {
        let url = try actionConfigurationURL()
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.tailops.decode(TailnetActionConfiguration.self, from: data)
    }

    public func saveActionConfiguration(_ configuration: TailnetActionConfiguration) throws {
        let url = try actionConfigurationURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.tailops.encode(configuration)
        try data.write(to: url, options: [.atomic])
    }

    private func snapshotURL() throws -> URL {
        try baseURL().appending(path: "tailops-snapshot.json")
    }

    private func actionConfigurationURL() throws -> URL {
        try baseURL().appending(path: "tailops-actions.json")
    }

    private func baseURL() throws -> URL {
        let baseURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
            ?? fallbackApplicationSupportURL()
        return baseURL
    }

    private func fallbackApplicationSupportURL() -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appending(path: "TailOpsMac", directoryHint: .isDirectory)
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
