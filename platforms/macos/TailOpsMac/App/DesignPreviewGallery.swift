import SwiftUI
import TailOpsCore
import TailOpsShared

#if DEBUG
#Preview("Menu Panel") {
    let store = InMemoryTailOpsStore(snapshot: .preview, actionConfiguration: .preview)
    TailOpsMenuView(
        monitor: TailnetMonitor(
            statusProvider: DesignPreviewStatusProvider(),
            tailnetStore: store,
            settingsStore: store,
            requestStore: store,
            initialSnapshot: .preview
        )
    )
    .frame(width: 360, height: 520)
}

#Preview("Host Row Density") {
    let store = InMemoryTailOpsStore(snapshot: .preview, actionConfiguration: .preview)
    VStack(spacing: 10) {
        TailOpsMenuView(
            monitor: TailnetMonitor(
                statusProvider: DesignPreviewStatusProvider(),
                tailnetStore: store,
                settingsStore: store,
                requestStore: store,
                initialSnapshot: .preview
            )
        )
    }
    .frame(width: 360, height: 520)
}

#Preview("Action Settings") {
    let store = InMemoryTailOpsStore(snapshot: .preview, actionConfiguration: .preview)
    TailOpsSettingsView(
        model: TailOpsActionSettingsModel(
            tailnetStore: store,
            settingsStore: store,
            configuration: .preview
        ),
        preferencesModel: TailOpsPreferencesModel(settingsStore: store)
    )
}

private struct DesignPreviewStatusProvider: TailscaleStatusProviding {
    func statusJSON() async throws -> Data {
        Data()
    }
}

#endif
