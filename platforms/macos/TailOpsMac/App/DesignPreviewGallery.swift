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
}
#endif
