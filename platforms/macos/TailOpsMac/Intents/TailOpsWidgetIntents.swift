import AppIntents
import AppKit
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
