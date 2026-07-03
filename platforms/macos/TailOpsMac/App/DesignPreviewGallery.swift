import SwiftUI
import TailOpsCore
import TailOpsShared

#if DEBUG
#Preview("Menu Panel") {
    TailOpsMenuView(
        monitor: TailnetMonitor(
            statusProvider: DesignPreviewStatusProvider(),
            snapshotStore: DesignPreviewSnapshotStore(),
            initialSnapshot: .preview
        )
    )
    .frame(width: 360, height: 520)
}

#Preview("Host Row Density") {
    VStack(spacing: 10) {
        TailOpsMenuView(
            monitor: TailnetMonitor(
                statusProvider: DesignPreviewStatusProvider(),
                snapshotStore: DesignPreviewSnapshotStore(),
                initialSnapshot: .preview
            )
        )
    }
    .frame(width: 360, height: 520)
}

#Preview("Action Settings") {
    TailOpsSettingsView(
        model: TailOpsActionSettingsModel(
            store: DesignPreviewSnapshotStore(),
            configuration: .preview
        )
    )
}

private struct DesignPreviewStatusProvider: TailscaleStatusProviding {
    func statusJSON() async throws -> Data {
        Data()
    }
}

private struct DesignPreviewSnapshotStore: SharedSnapshotStoring {
    func load() throws -> TailnetSnapshot? {
        .preview
    }

    func save(_ snapshot: TailnetSnapshot) throws {}

    func loadActionConfiguration() throws -> TailnetActionConfiguration? {
        .preview
    }

    func saveActionConfiguration(_ configuration: TailnetActionConfiguration) throws {}

    func loadAppPreferences() throws -> TailOpsAppPreferences? {
        TailOpsAppPreferences()
    }

    func saveAppPreferences(_ preferences: TailOpsAppPreferences) throws {}
    func loadWormholeConfiguration() throws -> TailOpsWormholeConfiguration? { TailOpsWormholeConfiguration() }
    func saveWormholeConfiguration(_ configuration: TailOpsWormholeConfiguration) throws {}
    func loadWormholeOpenRequest() throws -> TailOpsWormholeOpenRequest? { nil }
    func saveWormholeOpenRequest(_ request: TailOpsWormholeOpenRequest) throws {}
    func clearWormholeOpenRequest() throws {}
    func loadWormholePendingTransfers() throws -> [TailOpsWormholePendingTransfer] { [] }
    func saveWormholePendingTransfers(_ transfers: [TailOpsWormholePendingTransfer]) throws {}

    func loadSettingsOpenRequest() throws -> TailOpsSettingsOpenRequest? { nil }
    func saveSettingsOpenRequest(_ request: TailOpsSettingsOpenRequest) throws {}
    func clearSettingsOpenRequest() throws {}
}
#endif
