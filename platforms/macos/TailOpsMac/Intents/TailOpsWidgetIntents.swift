import AppIntents
import AppKit
import TailOpsCore
import TailOpsShared
import WidgetKit

public struct CopyTailnetValueIntent: AppIntent {
    public static let title: LocalizedStringResource = "Copy Tailnet Value"
    public static let description = IntentDescription("Copies a configured TailOps value, such as a Tailscale IP address.")
    public static let openAppWhenRun = false

    @Parameter(title: "Value")
    public var value: String

    public init() {
        value = ""
    }

    public init(value: String) {
        self.value = value
    }

    public func perform() async throws -> some IntentResult {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        return .result()
    }
}

public struct RefreshTailOpsWidgetIntent: AppIntent {
    public static let title: LocalizedStringResource = "Refresh TailOps Widget"
    public static let description = IntentDescription("Asks WidgetKit to reload TailOps widget timelines.")
    public static let openAppWhenRun = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "dev.tailops.monitor.widget")
        return .result()
    }
}

public struct OpenTailscaleAppIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Tailscale"
    public static let description = IntentDescription("Opens the Tailscale macOS app.")
    public static let openAppWhenRun = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let candidateURLs = [
            URL(fileURLWithPath: "/Applications/Tailscale.app"),
            URL(fileURLWithPath: "/System/Volumes/Data/Applications/Tailscale.app")
        ]

        if let url = candidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(url)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macsys") {
            NSWorkspace.shared.open(url)
        }

        return .result()
    }
}

public struct OpenTailOpsSettingsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open TailOps Settings"
    public static let description = IntentDescription("Opens TailOps settings from the widget.")
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        try SharedSnapshotStore().saveSettingsOpenRequest(TailOpsSettingsOpenRequest())
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(TailOpsSettingsOpenSignal.notificationName),
            object: nil,
            deliverImmediately: true
        )
        return .result()
    }
}
