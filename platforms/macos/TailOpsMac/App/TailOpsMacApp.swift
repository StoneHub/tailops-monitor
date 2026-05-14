import AppKit
import SwiftUI
import TailOpsCore
import TailOpsShared

@MainActor
final class TailOpsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = TaildropServiceProvider.shared
        NSUpdateDynamicServices()
    }
}

@main
struct TailOpsMacApp: App {
    @NSApplicationDelegateAdaptor(TailOpsAppDelegate.self) private var appDelegate
    @StateObject private var monitor: TailnetMonitor

    init() {
        let monitor = TailnetMonitor(
            statusProvider: ProcessTailscaleStatusProvider(),
            pingProvider: ProcessTailscalePingProvider(),
            snapshotStore: SharedSnapshotStore()
        )
        _monitor = StateObject(wrappedValue: monitor)
        Task { @MainActor in
            await monitor.refresh()
        }
    }

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
