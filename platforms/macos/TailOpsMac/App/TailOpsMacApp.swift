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
            selector: #selector(openWormholeWindowFromDistributedNotification),
            name: Notification.Name(TailOpsWormholeSignal.notificationName),
            object: nil
        )
        Self.openWormholeWindowIfRequested()
        TailOpsWormholePendingSignalServer.shared.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
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
        urls.forEach(Self.route)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.openSettingsWindow()
        return true
    }

    static func openSettingsWindow() {
        TailOpsSettingsWindowController.shared.show()
    }

    static func openWormholeWindowIfRequested(
        store: any TailOpsAppGroupRequestStoring = SharedSnapshotStore()
    ) {
        guard let request = try? store.loadWormholeOpenRequest() else {
            return
        }

        try? store.clearWormholeOpenRequest()
        guard request.isFresh() else { return }
        openWormholeWindow(request: request)
    }

    static func openWormholeWindow(request: TailOpsWormholeOpenRequest? = nil) {
        TailOpsWormholeWindowController.shared.show(request: request)
    }

    @objc private func openWormholeWindowFromDistributedNotification(_ notification: Notification) {
        let store = SharedSnapshotStore()
        let request = try? store.loadWormholeOpenRequest()
        try? store.clearWormholeOpenRequest()
        Self.openWormholeWindow(request: request)
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString)
        else {
            return
        }
        Self.route(url)
    }

    /// The Apple Event handler replaces AppKit's default URL delivery, so both
    /// entry points funnel through this one router.
    private static func route(_ url: URL) {
        guard url.scheme == TailOpsSettingsOpenSignal.url.scheme else { return }
        switch url.host {
        case TailOpsSettingsOpenSignal.url.host:
            openSettingsWindow()
        case TailOpsWormholeSignal.url.host:
            openWormholeWindow()
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
        let store = SharedSnapshotStore()
        let monitor = TailnetMonitor(
            statusProvider: ProcessTailscaleStatusProvider(),
            pingProvider: ProcessTailscalePingProvider(),
            healthProvider: SSHFleetHealthProvider(),
            healthSources: { FleetHealthSettings.sources() },
            tailnetStore: store,
            requestStore: store
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
            monitor.startObservingSystemEvents()
        }
    }

    var body: some Scene {
        Settings {
            TailOpsSettingsView(preferencesModel: preferencesModel)
        }
    }
}
