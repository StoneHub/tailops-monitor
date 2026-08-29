import Foundation
import TailOpsCore

#if DEBUG
public extension TailnetSnapshot {
    static let preview = TailnetSnapshot(hosts: [
        TailnetHost(
            id: "mac",
            name: "monroe-mac",
            role: .thisDevice,
            status: .online,
            operatingSystem: "macOS",
            primaryAddress: "100.64.0.1",
            magicDNSName: "monroe-mac.tailnet.ts.net",
            lastSeen: nil,
            services: []
        ),
        TailnetHost(
            id: "openclaw",
            name: "openclaw",
            role: .peer,
            status: .online,
            operatingSystem: "linux",
            primaryAddress: "100.64.0.2",
            magicDNSName: "openclaw.tailnet.ts.net",
            lastSeen: Date(timeIntervalSinceNow: -90),
            services: [
                TailnetService(label: "OpenClaw", url: URL(string: "http://openclaw.tailnet.ts.net:8080")!)
            ],
            diagnostics: TailnetHostDiagnostics(ping: .previewDirect)
        ),
        TailnetHost(
            id: "router",
            name: "asus-router",
            role: .peer,
            status: .warning,
            operatingSystem: "asuswrt",
            primaryAddress: "100.64.0.3",
            magicDNSName: "router.tailnet.ts.net",
            lastSeen: Date(timeIntervalSinceNow: -240),
            services: [
                TailnetService(label: "Router", url: URL(string: "http://router.tailnet.ts.net")!)
            ],
            diagnostics: TailnetHostDiagnostics(ping: .previewRelay)
        ),
        TailnetHost(
            id: "pixel",
            name: "pixel-test",
            role: .peer,
            status: .offline,
            operatingSystem: "android",
            primaryAddress: "100.64.0.4",
            magicDNSName: "pixel-test.tailnet.ts.net",
            lastSeen: Date(timeIntervalSinceNow: -3600),
            services: []
        )
    ])
}

public extension TailnetPingSummary {
    static let previewDirect = TailnetPingSummary(samples: [
        TailnetPingSample(latencyMilliseconds: 45, route: .derp),
        TailnetPingSample(latencyMilliseconds: 32, route: .derp),
        TailnetPingSample(latencyMilliseconds: 18, route: .direct),
        TailnetPingSample(latencyMilliseconds: 10, route: .direct),
        TailnetPingSample(latencyMilliseconds: 12, route: .direct),
        TailnetPingSample(latencyMilliseconds: 9, route: .direct)
    ])

    static let previewRelay = TailnetPingSummary(samples: [
        TailnetPingSample(latencyMilliseconds: 140, route: .derp),
        TailnetPingSample(latencyMilliseconds: 110, route: .peerRelay),
        TailnetPingSample(latencyMilliseconds: 126, route: .peerRelay),
        TailnetPingSample(latencyMilliseconds: 90, route: .peerRelay),
        TailnetPingSample(latencyMilliseconds: 115, route: .peerRelay)
    ])
}

public extension TailnetActionConfiguration {
    static let preview = TailnetActionConfiguration(hostActions: [
        TailnetHostActionConfiguration(
            hostID: "openclaw",
            actions: [
                TailnetQuickAction(emoji: "🖥", title: "SSH", kind: .ssh, target: "openclaw.tailnet.ts.net"),
                TailnetQuickAction(emoji: "🧭", title: "Dash", kind: .url, target: "http://openclaw.tailnet.ts.net:8080"),
                TailnetQuickAction(emoji: "📋", title: "IP", kind: .copy, target: "100.64.0.2")
            ]
        ),
        TailnetHostActionConfiguration(
            hostID: "asus-router",
            actions: [
                TailnetQuickAction(emoji: "📡", title: "Admin", kind: .url, target: "http://router.tailnet.ts.net"),
                TailnetQuickAction(emoji: "📋", title: "IP", kind: .copy, target: "100.64.0.3")
            ]
        ),
        TailnetHostActionConfiguration(
            hostID: "monroe-mac",
            actions: [
                TailnetQuickAction(emoji: "🏠", title: "Local", kind: .url, target: "http://127.0.0.1:4173"),
                TailnetQuickAction(emoji: "📋", title: "IP", kind: .copy, target: "100.64.0.1")
            ]
        )
    ])
}

public final class InMemoryTailOpsStore: @unchecked Sendable,
    TailnetStateStoring,
    TailOpsSettingsStoring,
    TailOpsWormholeStateStoring,
    TailOpsAppGroupRequestStoring
{
    private let lock = NSLock()
    private var snapshot: TailnetSnapshot?
    private var actionConfiguration: TailnetActionConfiguration?
    private var appPreferences: TailOpsAppPreferences?
    private var wormholeConfiguration: TailOpsWormholeConfiguration?
    private var wormholePendingTransfers: [TailOpsWormholePendingTransfer]
    private var wormholeSignalReplayRecords: [TailOpsWormholeSignalReplayRecord]
    private var settingsOpenRequest: TailOpsSettingsOpenRequest?
    private var refreshRequest: TailOpsRefreshRequest?
    private var wormholeOpenRequest: TailOpsWormholeOpenRequest?
    private var refreshHealth: TailOpsRefreshHealth?

    public init(
        snapshot: TailnetSnapshot? = nil,
        actionConfiguration: TailnetActionConfiguration? = nil,
        appPreferences: TailOpsAppPreferences? = nil,
        wormholeConfiguration: TailOpsWormholeConfiguration? = nil,
        wormholePendingTransfers: [TailOpsWormholePendingTransfer] = [],
        wormholeSignalReplayRecords: [TailOpsWormholeSignalReplayRecord] = [],
        settingsOpenRequest: TailOpsSettingsOpenRequest? = nil,
        refreshRequest: TailOpsRefreshRequest? = nil,
        wormholeOpenRequest: TailOpsWormholeOpenRequest? = nil,
        refreshHealth: TailOpsRefreshHealth? = nil
    ) {
        self.snapshot = snapshot
        self.actionConfiguration = actionConfiguration
        self.appPreferences = appPreferences
        self.wormholeConfiguration = wormholeConfiguration
        self.wormholePendingTransfers = wormholePendingTransfers
        self.wormholeSignalReplayRecords = wormholeSignalReplayRecords
        self.settingsOpenRequest = settingsOpenRequest
        self.refreshRequest = refreshRequest
        self.wormholeOpenRequest = wormholeOpenRequest
        self.refreshHealth = refreshHealth
    }

    public func load() throws -> TailnetSnapshot? {
        withLock { snapshot }
    }

    public func save(_ snapshot: TailnetSnapshot) throws {
        withLock { self.snapshot = snapshot }
    }

    public func loadRefreshHealth() throws -> TailOpsRefreshHealth? {
        withLock { refreshHealth }
    }

    public func saveRefreshHealth(_ health: TailOpsRefreshHealth) throws {
        withLock { refreshHealth = health }
    }

    public func loadActionConfiguration() throws -> TailnetActionConfiguration? {
        withLock { actionConfiguration }
    }

    public func saveActionConfiguration(_ configuration: TailnetActionConfiguration) throws {
        withLock { actionConfiguration = configuration }
    }

    public func loadAppPreferences() throws -> TailOpsAppPreferences? {
        withLock { appPreferences }
    }

    public func saveAppPreferences(_ preferences: TailOpsAppPreferences) throws {
        withLock { appPreferences = preferences }
    }

    public func loadWormholeConfiguration() throws -> TailOpsWormholeConfiguration? {
        withLock { wormholeConfiguration }
    }

    public func loadWormholeConfigurationMigratingSecrets(
        to secretStore: any TailOpsWormholeSecretStoring
    ) throws -> TailOpsWormholeConfiguration? {
        withLock { wormholeConfiguration }
    }

    public func saveWormholeConfiguration(_ configuration: TailOpsWormholeConfiguration) throws {
        withLock { wormholeConfiguration = configuration }
    }

    public func loadWormholePendingTransfers() throws -> [TailOpsWormholePendingTransfer] {
        withLock { wormholePendingTransfers.filter { !$0.isExpired() } }
    }

    public func saveWormholePendingTransfers(_ transfers: [TailOpsWormholePendingTransfer]) throws {
        withLock { wormholePendingTransfers = transfers.filter { !$0.isExpired() } }
    }

    public func loadWormholeSignalReplayRecords(
        at date: Date
    ) throws -> [TailOpsWormholeSignalReplayRecord] {
        withLock {
            Array(wormholeSignalReplayRecords.filter { $0.expiresAt > date }.suffix(256))
        }
    }

    public func saveWormholeSignalReplayRecords(
        _ records: [TailOpsWormholeSignalReplayRecord],
        at date: Date
    ) throws {
        withLock {
            wormholeSignalReplayRecords = Array(records.filter { $0.expiresAt > date }.suffix(256))
        }
    }

    public func loadSettingsOpenRequest() throws -> TailOpsSettingsOpenRequest? {
        withLock { settingsOpenRequest }
    }

    public func saveSettingsOpenRequest(_ request: TailOpsSettingsOpenRequest) throws {
        withLock { settingsOpenRequest = request }
    }

    public func clearSettingsOpenRequest() throws {
        withLock { settingsOpenRequest = nil }
    }

    public func loadRefreshRequest() throws -> TailOpsRefreshRequest? {
        withLock { refreshRequest }
    }

    public func saveRefreshRequest(_ request: TailOpsRefreshRequest) throws {
        withLock { refreshRequest = request }
    }

    public func clearRefreshRequest() throws {
        withLock { refreshRequest = nil }
    }

    public func loadWormholeOpenRequest() throws -> TailOpsWormholeOpenRequest? {
        withLock { wormholeOpenRequest }
    }

    public func saveWormholeOpenRequest(_ request: TailOpsWormholeOpenRequest) throws {
        withLock { wormholeOpenRequest = request }
    }

    public func clearWormholeOpenRequest() throws {
        withLock { wormholeOpenRequest = nil }
    }

    private func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
#endif
