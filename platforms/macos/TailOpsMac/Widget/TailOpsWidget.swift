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
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
        .containerBackgroundRemovable(true)
        .contentMarginsDisabled()
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
        VStack(alignment: .leading, spacing: verticalSpacing) {
            HStack {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .imageScale(.small)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 18, height: 18)
                Text("TailOps")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 7) {
                    Button(intent: OpenTailscaleAppIntent()) {
                        Label("Tailscale", systemImage: "arrow.up.forward.app")
                            .labelStyle(.iconOnly)
                    }
                    Button(intent: RefreshTailOpsWidgetIntent()) {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(entry.date, style: .time)
                        .monospacedDigit()
                    Button(intent: OpenTailOpsSettingsIntent()) {
                        Image(systemName: "gearshape")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }

            if entry.snapshot.hosts.isEmpty {
                WidgetEmptyState()
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(layout.visibleHosts) { host in
                        WidgetHostActionRow(
                            host: host,
                            actions: actionCatalog.actions(for: host),
                            showsActions: showsHostActions,
                            isCompact: usesCompactRows
                        )
                    }
                    if layout.hiddenOfflineCount > 0 {
                        WidgetOfflineSummary(count: layout.hiddenOfflineCount)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            TailOpsWidgetBackground(renderingMode: renderingMode)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    private var symbol: String {
        "point.3.connected.trianglepath.dotted"
    }

    private var visibleHostLimit: Int {
        switch family {
        case .systemSmall:
            return 1
        case .systemMedium:
            return 2
        case .systemExtraLarge:
            return 4
        case .systemLarge:
            return 2
        default:
            return 2
        }
    }

    private var showsHostActions: Bool {
        switch family {
        case .systemSmall:
            return false
        default:
            return true
        }
    }

    private var usesCompactRows: Bool {
        switch family {
        case .systemLarge, .systemExtraLarge:
            return false
        default:
            return true
        }
    }

    private var rowSpacing: CGFloat {
        switch family {
        case .systemExtraLarge:
            return 8
        case .systemLarge:
            return 7
        default:
            return 4
        }
    }

    private var verticalSpacing: CGFloat {
        switch family {
        case .systemLarge, .systemExtraLarge:
            return 10
        default:
            return 6
        }
    }

    private var horizontalPadding: CGFloat {
        switch family {
        case .systemSmall:
            return 12
        default:
            return 14
        }
    }

    private var verticalPadding: CGFloat {
        switch family {
        case .systemSmall:
            return 9
        case .systemMedium:
            return 12
        case .systemLarge:
            return 24
        case .systemExtraLarge:
            return 26
        default:
            return 14
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
    let showsActions: Bool
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: host.status))
                        .frame(width: 7, height: 7)
                    Text(host.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(detailText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let pingText {
                Text(pingText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            if showsActions {
                HStack(spacing: 4) {
                    ForEach(actions.prefix(2), id: \.title) { action in
                        WidgetActionChip(action: action)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isCompact ? 5 : 6)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if let samples = host.diagnostics?.ping?.samples {
                PingSparklineView(samples: samples)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .opacity(0.11)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
            }
        }
    }

    private var detailText: String {
        host.primaryAddress ?? host.magicDNSName ?? host.status.rawValue
    }

    private var pingText: String? {
        guard let ping = host.diagnostics?.ping,
              let latest = ping.latestLatencyMilliseconds,
              let average = ping.averageLatencyMilliseconds
        else {
            return nil
        }

        let latestText = latest.formatted(.number.precision(.fractionLength(0...0)))
        let averageText = average.formatted(.number.precision(.fractionLength(0...0)))
        return "\(latestText) ms / \(averageText) avg"
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
        if action.kind == .ssh, let value = action.value {
            Button(intent: OpenSSHInTerminalIntent(host: value)) {
                chipContent
            }
            .buttonStyle(.plain)
        } else if let url = action.url {
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
        Image(systemName: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.primary.opacity(0.8))
            .frame(width: 22, height: 22)
            .background(Color.primary.opacity(0.1), in: Circle())
            .accessibilityLabel(action.title)
    }

    private var systemImage: String {
        switch action.kind {
        case .ssh:
            return "terminal"
        case .dashboard:
            return "gauge.with.dots.needle.50percent"
        case .copyAddress:
            return "doc.on.doc"
        }
    }
}

#if DEBUG
#Preview("Widget View") {
    TailOpsWidgetView(entry: TailOpsEntry(date: .now, snapshot: .preview, actionConfiguration: .preview))
        .frame(width: 340, height: 240)
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
