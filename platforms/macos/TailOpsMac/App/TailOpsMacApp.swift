import SwiftUI
import TailOpsCore
import TailOpsShared

@main
struct TailOpsMacApp: App {
    @StateObject private var monitor = TailnetMonitor(
        statusProvider: ProcessTailscaleStatusProvider(),
        snapshotStore: SharedSnapshotStore()
    )

    var body: some Scene {
        MenuBarExtra {
            TailOpsMenuView(monitor: monitor)
                .frame(width: 360)
                .task {
                    await monitor.refresh()
                }
        } label: {
            TailOpsConstellationIcon(trafficLight: monitor.summary.trafficLight)
                .frame(width: 18, height: 18)
                .help("TailOps")
        }
        .menuBarExtraStyle(.window)

        Settings {
            TailOpsSettingsView()
        }
    }
}
