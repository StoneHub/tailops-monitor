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

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "tailops" && $0.host == "settings" }) else {
            return
        }

        Self.openSettingsWindow()
    }

    static func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

@main
struct TailOpsMacApp: App {
    @NSApplicationDelegateAdaptor(TailOpsAppDelegate.self) private var appDelegate
    @StateObject private var monitor: TailnetMonitor
    @StateObject private var preferencesModel: TailOpsPreferencesModel

    init() {
        let monitor = TailnetMonitor(
            statusProvider: ProcessTailscaleStatusProvider(),
            pingProvider: ProcessTailscalePingProvider(),
            snapshotStore: SharedSnapshotStore()
        )
        _monitor = StateObject(wrappedValue: monitor)
        _preferencesModel = StateObject(wrappedValue: TailOpsPreferencesModel())
        Task { @MainActor in
            await monitor.refresh()
        }
    }

    var body: some Scene {
        MenuBarExtra(
            "TailOps",
            systemImage: "point.3.connected.trianglepath.dotted",
            isInserted: $preferencesModel.showMenuBarIcon
        ) {
            TailOpsMenuView(monitor: monitor)
                .frame(width: 360)
                .task {
                    await monitor.refresh()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            TailOpsSettingsView(preferencesModel: preferencesModel)
        }
    }
}
