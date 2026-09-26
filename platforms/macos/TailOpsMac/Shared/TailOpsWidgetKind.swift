import WidgetKit

public enum TailOpsWidgetKind {
    public static let identifier = "dev.tailops.monitor.widget"

    /// The widget does not poll, so every change to state it displays must
    /// reload its timeline.
    public static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: identifier)
    }
}
