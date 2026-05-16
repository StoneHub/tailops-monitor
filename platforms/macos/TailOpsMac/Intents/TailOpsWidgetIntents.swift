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

public struct OpenSSHInTerminalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open SSH in Terminal"
    public static let description = IntentDescription("Opens an SSH session in Terminal.")
    public static let openAppWhenRun = false

    @Parameter(title: "Host")
    public var host: String

    public init() {
        host = ""
    }

    public init(host: String) {
        self.host = host
    }

    public func perform() async throws -> some IntentResult {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty,
              let sshURL = URL(string: "ssh://\(target)")
        else {
            return .result()
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            try await NSWorkspace.shared.open(
                [sshURL],
                withApplicationAt: terminalURL,
                configuration: configuration
            )
        } else {
            try await NSWorkspace.shared.open(sshURL, configuration: configuration)
        }

        return .result()
    }
}

public struct OpenDashboardURLIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Dashboard"
    public static let description = IntentDescription("Opens a TailOps dashboard URL in the default browser.")
    public static let openAppWhenRun = false

    @Parameter(title: "URL")
    public var urlString: String

    public init() {
        urlString = ""
    }

    public init(url: URL) {
        urlString = url.absoluteString
    }

    public func perform() async throws -> some IntentResult {
        let target = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: target),
              ["http", "https"].contains(url.scheme?.lowercased())
        else {
            return .result()
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.open(url, configuration: configuration)
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
