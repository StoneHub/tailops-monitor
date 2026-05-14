import SwiftUI
import TailOpsCore
import TailOpsShared

@main
struct TailOpsMacApp: App {
    @StateObject private var monitor = TailnetMonitor(
        statusProvider: ProcessTailscaleStatusProvider(),
        pingProvider: ProcessTailscalePingProvider(),
        snapshotStore: SharedSnapshotStore()
    )

    var body: some Scene {
        MenuBarExtra("TailOps", systemImage: "point.3.connected.trianglepath.dotted") {
            TailOpsMenuView(monitor: monitor)
                .frame(width: 360)
                .task {
                    await monitor.refresh()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            TailOpsSettingsView()
        }
    }
}
