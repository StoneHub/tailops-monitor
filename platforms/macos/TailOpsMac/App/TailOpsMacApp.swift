import AppKit
import SwiftUI
import TailOpsCore
import TailOpsShared

@MainActor
final class TailOpsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = TaildropServiceProvider.shared
        NSUpdateDynamicServices()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openSettingsWindowFromDistributedNotification),
            name: Notification.Name(TailOpsSettingsOpenSignal.notificationName),
            object: nil
        )
        Self.openSettingsWindowIfRequested()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Self.openSettingsWindowIfRequested()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "tailops" && $0.host == "settings" }) else {
            return
        }

        Self.openSettingsWindow()
    }

    static func openSettingsWindowIfRequested(store: SharedSnapshotStore = SharedSnapshotStore()) {
        guard (try? store.loadSettingsOpenRequest()) != nil else {
            return
        }

        try? store.clearSettingsOpenRequest()
        openSettingsWindow()
    }

    static func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func openSettingsWindowFromDistributedNotification(_ notification: Notification) {
        Self.openSettingsWindowIfRequested()
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
