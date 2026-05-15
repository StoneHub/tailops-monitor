import AppKit
import SwiftUI
import TailOpsCore
import TailOpsShared

@MainActor
final class TailOpsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

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
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "tailops" && $0.host == "settings" }) else {
            return
        }

        Self.openSettingsWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.openSettingsWindow()
        return true
    }

    static func openSettingsWindowIfRequested(store: SharedSnapshotStore = SharedSnapshotStore()) {
        guard (try? store.loadSettingsOpenRequest()) != nil else {
            return
        }

        try? store.clearSettingsOpenRequest()
        openSettingsWindow()
    }

    static func openSettingsWindow() {
        TailOpsSettingsWindowController.shared.show()
    }

    @objc private func openSettingsWindowFromDistributedNotification(_ notification: Notification) {
        try? SharedSnapshotStore().clearSettingsOpenRequest()
        Self.openSettingsWindow()
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "tailops",
              url.host == "settings"
        else {
            return
        }

        Self.openSettingsWindow()
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
        let preferencesModel = TailOpsPreferencesModel()
        TailOpsSettingsWindowController.shared.preferencesModel = preferencesModel
        _monitor = StateObject(wrappedValue: monitor)
        _preferencesModel = StateObject(wrappedValue: preferencesModel)
        Task { @MainActor in
            await monitor.refresh()
        }
    }

    var body: some Scene {
        Settings {
            TailOpsSettingsView(preferencesModel: preferencesModel)
        }
    }
}
