import Foundation
import ServiceManagement
import TailOpsCore
import TailOpsShared
import WidgetKit

@MainActor
final class TailOpsPreferencesModel: ObservableObject {
    @Published var launchAtLogin: Bool
    @Published var showMenuBarIcon: Bool
    @Published private(set) var saveError: String?
    @Published private(set) var statusMessage: String?

    private let store: SharedSnapshotStoring

    init(store: SharedSnapshotStoring = SharedSnapshotStore()) {
        self.store = store
        let storedPreferences = (try? store.loadAppPreferences()) ?? TailOpsAppPreferences()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        showMenuBarIcon = storedPreferences.showMenuBarIcon
    }

    var preferences: TailOpsAppPreferences {
        TailOpsAppPreferences(
            launchAtLogin: launchAtLogin,
            showMenuBarIcon: showMenuBarIcon,
            opensSettingsFromWidget: true
        )
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            save(message: enabled ? "TailOps will launch at login." : "TailOps will not launch at login.")
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            saveError = error.localizedDescription
        }
    }

    func setShowMenuBarIcon(_ enabled: Bool) {
        showMenuBarIcon = enabled
        save(message: enabled ? "Menu bar icon shown." : "Widget-only mode enabled.")
    }

    private func save(message: String) {
        do {
            try store.saveAppPreferences(preferences)
            WidgetCenter.shared.reloadTimelines(ofKind: "dev.tailops.monitor.widget")
            saveError = nil
            statusMessage = message
        } catch {
            saveError = error.localizedDescription
        }
    }
}
