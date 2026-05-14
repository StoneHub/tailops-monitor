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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var actionCatalog: HostActionCatalog {
        HostActionCatalog(configuration: entry.actionConfiguration)
    }

    private var layout: TailnetWidgetHostLayout {
        TailnetWidgetHostLayout(hosts: entry.snapshot.hosts, limit: visibleHostLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("TailOps", systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.hierarchical)
                Spacer()
                Button(intent: RefreshTailOpsWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if entry.snapshot.hosts.isEmpty {
                WidgetEmptyState()
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(layout.visibleHosts) { host in
                        WidgetHostActionRow(host: host, actions: actionCatalog.actions(for: host))
                    }
                    if layout.hiddenOfflineCount > 0 {
                        WidgetOfflineSummary(count: layout.hiddenOfflineCount)
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            TailOpsWidgetBackground(renderingMode: renderingMode)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var symbol: String {
        "point.3.connected.trianglepath.dotted"
    }

    private var visibleHostLimit: Int {
        switch family {
        case .systemSmall:
            return 1
        case .systemLarge:
            return 5
        default:
            return 2
        }
    }

    private var rowSpacing: CGFloat {
        switch family {
        case .systemLarge:
            return 8
        default:
            return 6
        }
    }
}

private struct WidgetEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Open TailOps to refresh")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Waiting for the shared tailnet snapshot.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
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

private struct WidgetOfflineSummary: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.secondary)
                .frame(width: 6, height: 6)
            Text("\(count) offline")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 1)
    }
}

private struct WidgetHostActionRow: View {
    let host: TailnetHost
    let actions: [HostAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color(for: host.status))
                    .frame(width: 7, height: 7)
                Text(host.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if let address = host.primaryAddress {
                    Text(address)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let pingText {
                Text(pingText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                    .opacity(0.18)
            }
        }
    }

    private var pingText: String? {
        guard let ping = host.diagnostics?.ping,
              let latest = ping.latestLatencyMilliseconds,
              let average = ping.averageLatencyMilliseconds
        else {
            return nil
        }

        let latestText = latest.formatted(.number.precision(.fractionLength(0...1)))
        let averageText = average.formatted(.number.precision(.fractionLength(0...1)))
        return "\(ping.latestRoute.label) \(latestText) ms | avg \(averageText) ms (\(ping.samples.count))"
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
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.primary.opacity(0.82))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.11), in: Capsule())
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
