import AppKit
import SwiftUI

@MainActor
final class TailOpsSettingsWindowController {
    static let shared = TailOpsSettingsWindowController()

    var preferencesModel: TailOpsPreferencesModel?

    private var window: NSWindow?
    private var hostingController: NSHostingController<TailOpsSettingsView>?

    private init() {}

    func show(preferencesModel: TailOpsPreferencesModel? = nil) {
        if let preferencesModel {
            self.preferencesModel = preferencesModel
        }

        let model = self.preferencesModel ?? TailOpsPreferencesModel()
        let settingsView = TailOpsSettingsView(preferencesModel: model)

        if let window, let hostingController {
            hostingController.rootView = settingsView
            show(window)
            return
        }

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "TailOps Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 500))
        window.minSize = NSSize(width: 560, height: 430)
        window.isReleasedWhenClosed = false
        window.center()

        self.hostingController = hostingController
        self.window = window
        show(window)
    }

    private func show(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
