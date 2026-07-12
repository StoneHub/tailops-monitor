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
        do {
            _ = try SharedSnapshotStore().loadWormholeConfigurationMigratingSecrets()
        } catch {
            NSLog("TailOps could not migrate Wormhole secrets to Keychain: %@", error.localizedDescription)
        }
        NSApp.servicesProvider = TaildropServiceProvider.shared
        NSUpdateDynamicServices()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openSettingsWindowFromDistributedNotification),
            name: Notification.Name(TailOpsSettingsOpenSignal.notificationName),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openWormholeWindowFromDistributedNotification),
            name: Notification.Name(TailOpsWormholeSignal.notificationName),
            object: nil
        )
        Self.openSettingsWindowIfRequested()
        Self.openWormholeWindowIfRequested()
        TailOpsWormholePendingSignalServer.shared.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Self.openSettingsWindowIfRequested()
        Self.openWormholeWindowIfRequested()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "tailops" {
            switch url.host {
            case "settings":
                Self.openSettingsWindow()
            case "wormhole":
                Self.openWormholeWindow()
            default:
                continue
            }
        }
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

    static func openWormholeWindowIfRequested(store: SharedSnapshotStore = SharedSnapshotStore()) {
        guard let request = try? store.loadWormholeOpenRequest() else {
            return
        }

        try? store.clearWormholeOpenRequest()
        openWormholeWindow(request: request)
    }

    static func openWormholeWindow(request: TailOpsWormholeOpenRequest? = nil) {
        TailOpsWormholeWindowController.shared.show(request: request)
    }

    @objc private func openSettingsWindowFromDistributedNotification(_ notification: Notification) {
        try? SharedSnapshotStore().clearSettingsOpenRequest()
        Self.openSettingsWindow()
    }

    @objc private func openWormholeWindowFromDistributedNotification(_ notification: Notification) {
        let store = SharedSnapshotStore()
        let request = try? store.loadWormholeOpenRequest()
        try? store.clearWormholeOpenRequest()
        Self.openWormholeWindow(request: request)
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "tailops"
        else {
            return
        }

        switch url.host {
        case "settings":
            Self.openSettingsWindow()
        case "wormhole":
            Self.openWormholeWindow()
        default:
            return
        }
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
            if !(await monitor.refreshIfRequested()) {
                await monitor.refresh()
            }
            monitor.startAutomaticRefresh()
        }
    }

    var body: some Scene {
        Settings {
            TailOpsSettingsView(preferencesModel: preferencesModel)
        }
    }
}
