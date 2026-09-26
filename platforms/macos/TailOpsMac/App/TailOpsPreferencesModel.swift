import Foundation
import ServiceManagement

/// Launch-at-login is the only app preference. macOS owns its state through
/// `SMAppService`, so TailOps reads it back instead of persisting a copy.
@MainActor
final class TailOpsPreferencesModel: ObservableObject {
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var saveError: String?
    @Published private(set) var statusMessage: String?

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            saveError = nil
            statusMessage = enabled ? "TailOps will launch at login." : "TailOps will not launch at login."
        } catch {
            saveError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
