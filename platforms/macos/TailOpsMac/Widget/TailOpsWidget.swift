import SwiftUI
import TailOpsCore
import TailOpsIntents
import TailOpsShared
import WidgetKit

struct TailOpsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.tailops.monitor.widget", provider: TailOpsTimelineProvider()) { entry in
            TailOpsWidgetView(entry: entry)
        }
        .configurationDisplayName("TailOps")
        .description("Glanceable Tailscale host reachability.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .containerBackgroundRemovable(true)
    }
}

struct TailOpsEntry: TimelineEntry {
    let date: Date
    let snapshot: TailnetSnapshot
    let actionConfiguration: TailnetActionConfiguration
}

struct TailOpsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TailOpsEntry {
        TailOpsEntry(date: Date(), snapshot: .preview, actionConfiguration: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TailOpsEntry) -> Void) {
        completion(TailOpsEntry(date: Date(), snapshot: loadSnapshot(), actionConfiguration: loadActionConfiguration()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TailOpsEntry>) -> Void) {
        let entry = TailOpsEntry(date: Date(), snapshot: loadSnapshot(), actionConfiguration: loadActionConfiguration())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSnapshot() -> TailnetSnapshot {
        (try? SharedSnapshotStore().load()) ?? TailnetSnapshot(hosts: [])
    }

    private func loadActionConfiguration() -> TailnetActionConfiguration {
        (try? SharedSnapshotStore().loadActionConfiguration()) ?? .preview
    }
}

struct TailOpsWidgetView: View {
    let entry: TailOpsEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground

    private var summary: TailnetSummary {
        TailnetSummary(hosts: entry.snapshot.hosts)
    }

    private var actionCatalog: HostActionCatalog {
        HostActionCatalog(configuration: entry.actionConfiguration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("TailOps", systemImage: symbol)
                    .font(.headline)
                    .widgetAccentable()
                Spacer()
                Button(intent: RefreshTailOpsWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(entry.snapshot.hosts.prefix(3)) { host in
                    WidgetHostActionRow(host: host, actions: actionCatalog.actions(for: host))
                }
            }
        }
        .containerBackground(for: .widget) {
            TailOpsWidgetBackground(renderingMode: renderingMode)
        }
        .padding()
    }

    private var symbol: String {
        switch summary.trafficLight {
        case .healthy:
            return "network"
        case .warning:
            return "exclamationmark.triangle"
        case .offline:
            return "wifi.slash"
        }
    }

    private func color(for status: TailnetHost.Status) -> Color {
        switch status {
        case .online:
            return .green
        case .warning:
            return .orange
        case .offline:
            return .red
        }
    }
}

private struct TailOpsWidgetBackground: View {
    let renderingMode: WidgetRenderingMode

    var body: some View {
        if renderingMode == .fullColor {
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.08),
                    Color.primary.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color.clear
        }
    }
}

private struct WidgetHostActionRow: View {
    let host: TailnetHost
    let actions: [HostAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color(for: host.status))
                    .frame(width: 7, height: 7)
                    .widgetAccentable(host.status != .offline)
                Text(host.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .widgetAccentable(host.status == .online)
                Spacer()
                if let address = host.primaryAddress {
                    Text(address)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 5) {
                ForEach(actions.prefix(3), id: \.title) { action in
                    WidgetActionChip(action: action)
                }
            }
        }
        .padding(.vertical, 2)
        .background {
            if let samples = host.diagnostics?.ping?.samples {
                PingSparklineView(samples: samples)
                    .padding(.vertical, 2)
                    .opacity(0.26)
            }
        }
    }

    private func color(for status: TailnetHost.Status) -> Color {
        switch status {
        case .online:
            return .green
        case .warning:
            return .orange
        case .offline:
            return .red
        }
    }
}

private struct WidgetActionChip: View {
    let action: HostAction

    var body: some View {
        if let url = action.url {
            Link(destination: url) {
                chipContent
            }
        } else if action.kind == .copyAddress, let value = action.value {
            Button(intent: CopyTailnetValueIntent(value: value)) {
                chipContent
            }
            .buttonStyle(.plain)
        } else {
            chipContent
                .foregroundStyle(.secondary)
        }
    }

    private var chipContent: some View {
        HStack(spacing: 3) {
            Text(action.emoji ?? fallbackEmoji)
            Text(action.title)
                .lineLimit(1)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
        .widgetAccentable(action.kind != .copyAddress)
    }

    private var fallbackEmoji: String {
        switch action.kind {
        case .ssh:
            return ">"
        case .dashboard:
            return "*"
        case .copyAddress:
            return "#"
        }
    }
}

#if DEBUG
#Preview("Widget View") {
    TailOpsWidgetView(entry: TailOpsEntry(date: .now, snapshot: .preview, actionConfiguration: .preview))
        .frame(width: 340, height: 180)
}

#Preview("Small", as: .systemSmall) {
    TailOpsWidget()
} timeline: {
    TailOpsEntry(date: .now, snapshot: .preview, actionConfiguration: .preview)
}

#Preview("Medium", as: .systemMedium) {
    TailOpsWidget()
} timeline: {
    TailOpsEntry(date: .now, snapshot: .preview, actionConfiguration: .preview)
}
#endif
