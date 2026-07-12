import Foundation
import Security
import TailOpsCore

public protocol SharedSnapshotStoring {
    func load() throws -> TailnetSnapshot?
    func save(_ snapshot: TailnetSnapshot) throws
    func loadActionConfiguration() throws -> TailnetActionConfiguration?
    func saveActionConfiguration(_ configuration: TailnetActionConfiguration) throws
    func loadAppPreferences() throws -> TailOpsAppPreferences?
    func saveAppPreferences(_ preferences: TailOpsAppPreferences) throws
    func loadWormholeConfiguration() throws -> TailOpsWormholeConfiguration?
    func saveWormholeConfiguration(_ configuration: TailOpsWormholeConfiguration) throws
    func loadWormholeOpenRequest() throws -> TailOpsWormholeOpenRequest?
    func saveWormholeOpenRequest(_ request: TailOpsWormholeOpenRequest) throws
    func clearWormholeOpenRequest() throws
    func loadWormholePendingTransfers() throws -> [TailOpsWormholePendingTransfer]
    func saveWormholePendingTransfers(_ transfers: [TailOpsWormholePendingTransfer]) throws
    func loadSettingsOpenRequest() throws -> TailOpsSettingsOpenRequest?
    func saveSettingsOpenRequest(_ request: TailOpsSettingsOpenRequest) throws
    func clearSettingsOpenRequest() throws
    func loadRefreshRequest() throws -> TailOpsRefreshRequest?
    func saveRefreshRequest(_ request: TailOpsRefreshRequest) throws
    func clearRefreshRequest() throws
    func loadRefreshHealth() throws -> TailOpsRefreshHealth?
    func saveRefreshHealth(_ health: TailOpsRefreshHealth) throws
}

public extension SharedSnapshotStoring {
    func loadRefreshRequest() throws -> TailOpsRefreshRequest? { nil }
    func saveRefreshRequest(_ request: TailOpsRefreshRequest) throws {}
    func clearRefreshRequest() throws {}
    func loadRefreshHealth() throws -> TailOpsRefreshHealth? { nil }
    func saveRefreshHealth(_ health: TailOpsRefreshHealth) throws {}
}

public protocol TailOpsWormholeSecretStoring: Sendable {
    func secret(for contactID: String) throws -> String?
    func save(secret: String, for contactID: String) throws
}

public enum TailOpsWormholeSecretStoreError: LocalizedError, Equatable {
    case invalidSecret
    case keychainFailure(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidSecret:
            return "The Wormhole setup secret is empty."
        case .keychainFailure(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "The Wormhole setup secret could not be accessed in Keychain (\(detail))."
        }
    }
}

public struct TailOpsWormholeSecretStore: TailOpsWormholeSecretStoring {
    public static let service = "dev.tailops.monitor.wormhole"

    public init() {}

    public func secret(for contactID: String) throws -> String? {
        var query = baseQuery(contactID: contactID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw TailOpsWormholeSecretStoreError.keychainFailure(status)
        }
        guard let data = result as? Data,
              let secret = String(data: data, encoding: .utf8),
              !secret.isEmpty
        else {
            throw TailOpsWormholeSecretStoreError.invalidSecret
        }
        return secret
    }

    public func save(secret: String, for contactID: String) throws {
        let cleanSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSecret.isEmpty else {
            throw TailOpsWormholeSecretStoreError.invalidSecret
        }

        let data = Data(cleanSecret.utf8)
        let query = baseQuery(contactID: contactID)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw TailOpsWormholeSecretStoreError.keychainFailure(updateStatus)
        }

        var insertion = query
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw TailOpsWormholeSecretStoreError.keychainFailure(addStatus)
        }
    }

    private func baseQuery(contactID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: contactID
        ]
    }
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

    public func loadAppPreferences() throws -> TailOpsAppPreferences? {
        try loadFirstExisting(path: "tailops-preferences.json", as: TailOpsAppPreferences.self)
    }

    public func saveAppPreferences(_ preferences: TailOpsAppPreferences) throws {
        let data = try JSONEncoder.tailops.encode(preferences)
        try write(data, path: "tailops-preferences.json")
    }

    public func loadWormholeConfiguration() throws -> TailOpsWormholeConfiguration? {
        try loadFirstExisting(path: "tailops-wormhole.json", as: TailOpsWormholeConfiguration.self)
    }

    /// Moves secrets from the legacy shared JSON file into Keychain. The shared
    /// file is rewritten only after every legacy secret has been stored.
    public func loadWormholeConfigurationMigratingSecrets(
        to secretStore: any TailOpsWormholeSecretStoring = TailOpsWormholeSecretStore()
    ) throws -> TailOpsWormholeConfiguration? {
        var existingConfigurations: [(
            url: URL,
            configuration: TailOpsWormholeConfiguration,
            sanitizedData: Data,
            containedSecretField: Bool,
            legacySecrets: [(contactID: String, secret: String)]
        )] = []

        for baseURL in try baseURLs() {
            let url = baseURL.appending(path: "tailops-wormhole.json")
            guard fileManager.fileExists(atPath: url.path) else { continue }

            let data = try Data(contentsOf: url)
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var contacts = object["contacts"] as? [[String: Any]]
            else {
                let configuration = try JSONDecoder.tailops.decode(
                    TailOpsWormholeConfiguration.self,
                    from: data
                )
                existingConfigurations.append((url, configuration, data, false, []))
                continue
            }

            var legacySecrets: [(contactID: String, secret: String)] = []
            var containedSecretField = false
            for index in contacts.indices {
                if contacts[index].keys.contains("sharedSecret") {
                    containedSecretField = true
                }
                if let contactID = contacts[index]["id"] as? String,
                   let secret = contacts[index]["sharedSecret"] as? String,
                   !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    legacySecrets.append((contactID, secret))
                }
                contacts[index].removeValue(forKey: "sharedSecret")
            }

            object["contacts"] = contacts
            let sanitizedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let configuration = try JSONDecoder.tailops.decode(
                TailOpsWormholeConfiguration.self,
                from: sanitizedData
            )

            existingConfigurations.append((
                url,
                configuration,
                sanitizedData,
                containedSecretField,
                legacySecrets
            ))
        }

        var migratedContactIDs = Set<String>()
        for existingConfiguration in existingConfigurations {
            for legacySecret in existingConfiguration.legacySecrets {
                guard migratedContactIDs.insert(legacySecret.contactID).inserted else { continue }
                if try secretStore.secret(for: legacySecret.contactID) == nil {
                    try secretStore.save(secret: legacySecret.secret, for: legacySecret.contactID)
                }
            }
        }
        for existingConfiguration in existingConfigurations where existingConfiguration.containedSecretField {
            try existingConfiguration.sanitizedData.write(
                to: existingConfiguration.url,
                options: [.atomic]
            )
        }

        return existingConfigurations.first?.configuration
    }

    public func saveWormholeConfiguration(_ configuration: TailOpsWormholeConfiguration) throws {
        let data = try JSONEncoder.tailops.encode(configuration)
        try write(data, path: "tailops-wormhole.json")
    }

    public func loadWormholeOpenRequest() throws -> TailOpsWormholeOpenRequest? {
        try loadFirstExisting(path: "tailops-open-wormhole.json", as: TailOpsWormholeOpenRequest.self)
    }

    public func saveWormholeOpenRequest(_ request: TailOpsWormholeOpenRequest) throws {
        let data = try JSONEncoder.tailops.encode(request)
        try write(data, path: "tailops-open-wormhole.json")
    }

    public func clearWormholeOpenRequest() throws {
        try delete(path: "tailops-open-wormhole.json")
    }

    public func loadWormholePendingTransfers() throws -> [TailOpsWormholePendingTransfer] {
        var firstTransfers: [TailOpsWormholePendingTransfer]?
        for baseURL in try baseURLs() {
            let url = baseURL.appending(path: "tailops-wormhole-pending.json")
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let data = try Data(contentsOf: url)
            let transfers = try JSONDecoder.tailops.decode([TailOpsWormholePendingTransfer].self, from: data)
                .filter { !$0.isExpired() }
            if firstTransfers == nil { firstTransfers = transfers }

            // Older builds persisted the live Wormhole code. Decoding ignores
            // that legacy key; rewrite immediately so it is removed at rest.
            if data.range(of: Data("\"code\"".utf8)) != nil {
                try JSONEncoder.tailops.encode(transfers).write(to: url, options: [.atomic])
            }
        }
        return firstTransfers ?? []
    }

    public func saveWormholePendingTransfers(_ transfers: [TailOpsWormholePendingTransfer]) throws {
        let activeTransfers = transfers.filter { !$0.isExpired() }
        let data = try JSONEncoder.tailops.encode(activeTransfers)
        try write(data, path: "tailops-wormhole-pending.json")
    }

    public func loadWormholeSignalReplayRecords(at date: Date = Date()) throws -> [TailOpsWormholeSignalReplayRecord] {
        let records = try loadFirstExisting(
            path: "tailops-wormhole-signal-replay.json",
            as: [TailOpsWormholeSignalReplayRecord].self
        ) ?? []
        return Array(records.filter { $0.expiresAt > date }.suffix(256))
    }

    public func saveWormholeSignalReplayRecords(
        _ records: [TailOpsWormholeSignalReplayRecord],
        at date: Date = Date()
    ) throws {
        let bounded = Array(records.filter { $0.expiresAt > date }.suffix(256))
        try write(JSONEncoder.tailops.encode(bounded), path: "tailops-wormhole-signal-replay.json")
    }

    public func loadSettingsOpenRequest() throws -> TailOpsSettingsOpenRequest? {
        try loadFirstExisting(path: "tailops-open-settings.json", as: TailOpsSettingsOpenRequest.self)
    }

    public func saveSettingsOpenRequest(_ request: TailOpsSettingsOpenRequest) throws {
        let data = try JSONEncoder.tailops.encode(request)
        try write(data, path: "tailops-open-settings.json")
    }

    public func clearSettingsOpenRequest() throws {
        try delete(path: "tailops-open-settings.json")
    }

    public func loadRefreshRequest() throws -> TailOpsRefreshRequest? {
        try loadFirstExisting(path: "tailops-refresh-request.json", as: TailOpsRefreshRequest.self)
    }

    public func saveRefreshRequest(_ request: TailOpsRefreshRequest) throws {
        let data = try JSONEncoder.tailops.encode(request)
        try write(data, path: "tailops-refresh-request.json")
    }

    public func clearRefreshRequest() throws {
        try delete(path: "tailops-refresh-request.json")
    }

    public func loadRefreshHealth() throws -> TailOpsRefreshHealth? {
        try loadFirstExisting(path: "tailops-refresh-health.json", as: TailOpsRefreshHealth.self)
    }

    public func saveRefreshHealth(_ health: TailOpsRefreshHealth) throws {
        let data = try JSONEncoder.tailops.encode(health)
        try write(data, path: "tailops-refresh-health.json")
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

    private func delete(path: String) throws {
        for baseURL in try baseURLs() {
            let url = baseURL.appending(path: path)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
        }
    }

    private func baseURLs() throws -> [URL] {
        if let baseURLOverride {
            return baseURLOverride
        }

        let appGroupURLs = Self.appGroupIdentifierCandidates.map {
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }

        return (appGroupURLs + [Optional(fallbackApplicationSupportURL())])
            .compactMap(\.self)
            .deduplicatedByPath()
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
