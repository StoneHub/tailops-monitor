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
    let refreshHealth: TailOpsRefreshHealth
    let wormholeConfiguration: TailOpsWormholeConfiguration
    let pendingWormholeTransfers: [TailOpsWormholePendingTransfer]
}

struct TailOpsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TailOpsEntry {
        TailOpsEntry(
            date: Date(),
            snapshot: TailnetSnapshot(hosts: []),
            actionConfiguration: TailnetActionConfiguration(),
            refreshHealth: TailOpsRefreshHealth(),
            wormholeConfiguration: TailOpsWormholeConfiguration(),
            pendingWormholeTransfers: []
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TailOpsEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TailOpsEntry>) -> Void) {
        let entry = entry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func entry() -> TailOpsEntry {
        TailOpsEntry(
            date: Date(),
            snapshot: loadSnapshot(),
            actionConfiguration: loadActionConfiguration(),
            refreshHealth: loadRefreshHealth(),
            wormholeConfiguration: loadWormholeConfiguration(),
            pendingWormholeTransfers: loadPendingWormholeTransfers()
        )
    }

    private func loadSnapshot() -> TailnetSnapshot {
        (try? SharedSnapshotStore().load()) ?? TailnetSnapshot(hosts: [])
    }

    private func loadActionConfiguration() -> TailnetActionConfiguration {
        (try? SharedSnapshotStore().loadActionConfiguration()) ?? TailnetActionConfiguration()
    }

    private func loadRefreshHealth() -> TailOpsRefreshHealth {
        (try? SharedSnapshotStore().loadRefreshHealth()) ?? TailOpsRefreshHealth()
    }

    private func loadWormholeConfiguration() -> TailOpsWormholeConfiguration {
        (try? SharedSnapshotStore().loadWormholeConfiguration()) ?? TailOpsWormholeConfiguration()
    }

    private func loadPendingWormholeTransfers() -> [TailOpsWormholePendingTransfer] {
        (try? SharedSnapshotStore().loadWormholePendingTransfers()) ?? []
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

    private var gridHosts: [TailnetHost] {
        Array(entry.snapshot.hosts.sorted(by: gridSort).prefix(gridHostLimit))
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
                    WidgetSnapshotFreshness(
                        generatedAt: entry.snapshot.generatedAt,
                        refreshHealth: entry.refreshHealth,
                        referenceDate: entry.date,
                        hasSnapshot: !entry.snapshot.hosts.isEmpty
                    )
                    Link(destination: TailOpsSettingsOpenSignal.url) {
                        Image(systemName: "gearshape")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }

            if entry.snapshot.hosts.isEmpty {
                WidgetEmptyState()
            } else if usesStatusGrid {
                WidgetHostStatusGrid(
                    hosts: gridHosts,
                    actionCatalog: actionCatalog,
                    wormholeConfiguration: entry.wormholeConfiguration,
                    pendingTransfers: entry.pendingWormholeTransfers,
                    style: gridStyle
                )
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(layout.visibleHosts) { host in
                        WidgetHostActionRow(
                            host: host,
                            actions: actionCatalog.actions(for: host),
                            wormholeContact: entry.wormholeConfiguration.contact(for: host),
                            pendingTransfer: entry.pendingWormholeTransfers.pendingTransfer(
                                for: entry.wormholeConfiguration.contact(for: host)
                            ),
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
        .widgetAccentable(false)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    private var symbol: String {
        "point.3.connected.trianglepath.dotted"
    }

    private var usesStatusGrid: Bool {
        switch family {
        case .systemLarge, .systemExtraLarge:
            return true
        default:
            return false
        }
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

    private var gridHostLimit: Int {
        switch family {
        case .systemExtraLarge:
            return 9
        case .systemLarge:
            return 6
        default:
            return visibleHostLimit
        }
    }

    private var gridColumnCount: Int {
        switch family {
        case .systemLarge, .systemExtraLarge:
            return 3
        default:
            return 2
        }
    }

    private var gridStyle: WidgetHostStatusGrid.Style {
        switch family {
        case .systemExtraLarge:
            return WidgetHostStatusGrid.Style(
                columns: gridColumnCount,
                columnSpacing: 7,
                rowSpacing: 6,
                tileMinHeight: 72,
                tileMaxHeight: nil,
                tileHorizontalPadding: 8,
                tileVerticalPadding: 6,
                tileContentSpacing: 5,
                showsActionTitles: true
            )
        default:
            return WidgetHostStatusGrid.Style(
                columns: gridColumnCount,
                columnSpacing: 10,
                rowSpacing: 10,
                tileMinHeight: 102,
                tileMaxHeight: 102,
                tileHorizontalPadding: 10,
                tileVerticalPadding: 8,
                tileContentSpacing: 7,
                showsActionTitles: false
            )
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
            return 6
        case .systemLarge:
            return 7
        default:
            return 4
        }
    }

    private var verticalSpacing: CGFloat {
        switch family {
        case .systemLarge:
            return 8
        case .systemExtraLarge:
            return 8
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
            return 18
        case .systemExtraLarge:
            return 12
        default:
            return 14
        }
    }

    private func gridSort(_ lhs: TailnetHost, _ rhs: TailnetHost) -> Bool {
        if lhs.role != rhs.role {
            return lhs.role == .peer
        }

        if statusRank(lhs.status) != statusRank(rhs.status) {
            return statusRank(lhs.status) < statusRank(rhs.status)
        }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func statusRank(_ status: TailnetHost.Status) -> Int {
        switch status {
        case .online:
            return 0
        case .warning:
            return 1
        case .offline:
            return 2
        }
    }
}

private struct WidgetSnapshotFreshness: View {
    let generatedAt: Date
    let refreshHealth: TailOpsRefreshHealth
    let referenceDate: Date
    let hasSnapshot: Bool

    private let staleInterval: TimeInterval = 90 * 60

    var body: some View {
        HStack(spacing: 3) {
            if refreshHealth.hasFailedSinceLastSuccess {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Failed")
            } else if isRefreshActive {
                ProgressView()
                    .controlSize(.mini)
                Text("Refreshing")
            } else if isStale {
                Image(systemName: "clock.badge.exclamationmark")
                Text("Stale")
            }

            if hasSnapshot {
                if showsStateLabel {
                    Text("·")
                }
                Text(generatedAt, style: .relative)
                    .monospacedDigit()
            } else {
                Text("No data")
            }
        }
        .foregroundStyle(showsWarning ? Color.orange : Color.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var isStale: Bool {
        hasSnapshot && referenceDate.timeIntervalSince(generatedAt) >= staleInterval
    }

    private var showsStateLabel: Bool {
        refreshHealth.hasFailedSinceLastSuccess || isRefreshActive || isStale
    }

    private var showsWarning: Bool {
        refreshHealth.hasFailedSinceLastSuccess || isStale
    }

    private var isRefreshActive: Bool {
        refreshHealth.isRefreshInProgress(at: referenceDate)
    }

    private var accessibilityText: String {
        guard hasSnapshot else { return "No tailnet snapshot available" }
        let age = RelativeDateTimeFormatter().localizedString(for: generatedAt, relativeTo: referenceDate)
        if refreshHealth.hasFailedSinceLastSuccess {
            return "Refresh failed. Snapshot generated \(age)"
        }
        if isRefreshActive {
            return "Refreshing. Snapshot generated \(age)"
        }
        if isStale {
            return "Snapshot stale. Generated \(age)"
        }
        return "Snapshot generated \(age)"
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
                    Color.green.opacity(0.15),
                    Color.blue.opacity(0.08),
                    Color.orange.opacity(0.08)
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

private struct WidgetHostStatusGrid: View {
    let hosts: [TailnetHost]
    let actionCatalog: HostActionCatalog
    let wormholeConfiguration: TailOpsWormholeConfiguration
    let pendingTransfers: [TailOpsWormholePendingTransfer]
    let style: Style

    struct Style {
        let columns: Int
        let columnSpacing: CGFloat
        let rowSpacing: CGFloat
        let tileMinHeight: CGFloat
        let tileMaxHeight: CGFloat?
        let tileHorizontalPadding: CGFloat
        let tileVerticalPadding: CGFloat
        let tileContentSpacing: CGFloat
        let showsActionTitles: Bool
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: style.columnSpacing, alignment: .top),
            count: max(style.columns, 1)
        )
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: style.rowSpacing) {
            ForEach(hosts) { host in
                WidgetHostStatusTile(
                    host: host,
                    actions: actionCatalog.actions(for: host),
                    wormholeContact: wormholeConfiguration.contact(for: host),
                    pendingTransfer: pendingTransfers.pendingTransfer(for: wormholeConfiguration.contact(for: host)),
                    style: style
                )
            }
        }
    }
}

private struct WidgetHostStatusTile: View {
    let host: TailnetHost
    let actions: [HostAction]
    let wormholeContact: TailOpsWormholeContact?
    let pendingTransfer: TailOpsWormholePendingTransfer?
    let style: WidgetHostStatusGrid.Style

    var body: some View {
        VStack(alignment: .leading, spacing: style.tileContentSpacing) {
            HStack(alignment: .top, spacing: 7) {
                statusMarker

                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    HStack(spacing: 5) {
                        Text(statusText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(color)
                            .lineLimit(1)

                        if let pingText {
                            Text(pingText)
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Text(detailText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let pendingTransfer {
                Text("Pending \(pendingTransfer.fileName)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            HStack(spacing: 5) {
                if let wormholeContact {
                    WidgetWormholeChip(mode: .send, contact: wormholeContact, showsTitle: style.showsActionTitles)
                    WidgetWormholeChip(
                        mode: .receive,
                        contact: wormholeContact,
                        pendingTransfer: pendingTransfer,
                        showsTitle: style.showsActionTitles
                    )
                }
                ForEach(actions.prefix(3), id: \.title) { action in
                    WidgetActionChip(action: action, showsTitle: style.showsActionTitles)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: style.tileMinHeight,
            maxHeight: style.tileMaxHeight,
            alignment: .topLeading
        )
        .padding(.horizontal, style.tileHorizontalPadding)
        .padding(.vertical, style.tileVerticalPadding)
        .background(tileBackground, in: RoundedRectangle(cornerRadius: 8))
        .widgetAccentable(false)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    pendingTransfer == nil
                        ? (wormholeContact == nil ? color.opacity(0.42) : Color.accentColor.opacity(0.72))
                        : Color.accentColor.opacity(0.95),
                    lineWidth: pendingTransfer == nil ? (wormholeContact == nil ? 1 : 1.5) : 2
                )
        }
    }

    private var detailText: String {
        host.primaryAddress ?? host.magicDNSName ?? host.operatingSystem ?? "No address"
    }

    private var pingText: String? {
        guard host.status != .offline,
              let latest = host.diagnostics?.ping?.latestLatencyMilliseconds
        else {
            return nil
        }

        let formatted = latest.formatted(.number.precision(.fractionLength(0...0)))
        return "\(formatted) ms"
    }

    private var statusText: String {
        switch host.status {
        case .online:
            return host.role == .thisDevice ? "This Mac" : "Online"
        case .warning:
            return "Warn"
        case .offline:
            return "Offline"
        }
    }

    private var statusIcon: String {
        switch host.status {
        case .online:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .offline:
            return "minus.circle.fill"
        }
    }

    private var statusMarker: some View {
        ZStack {
            Circle()
                .fill(color.opacity(host.status == .offline ? 0.18 : 0.26))
                .frame(width: 18, height: 18)
            Image(systemName: statusIcon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
        }
        .widgetAccentable(false)
    }

    private var tileBackground: LinearGradient {
        LinearGradient(
            colors: [
                color.opacity(host.status == .offline ? 0.09 : 0.2),
                Color.primary.opacity(0.045)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var color: Color {
        switch host.status {
        case .online:
            return .green
        case .warning:
            return .orange
        case .offline:
            return .secondary
        }
    }
}

private struct WidgetHostActionRow: View {
    let host: TailnetHost
    let actions: [HostAction]
    let wormholeContact: TailOpsWormholeContact?
    let pendingTransfer: TailOpsWormholePendingTransfer?
    let showsActions: Bool
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: host.status))
                        .frame(width: 7, height: 7)
                        .widgetAccentable(false)
                    Text(host.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(detailText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let pendingTransfer {
                    Text("Pending \(pendingTransfer.fileName)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
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
                    if let wormholeContact {
                        WidgetWormholeChip(mode: .send, contact: wormholeContact)
                        WidgetWormholeChip(mode: .receive, contact: wormholeContact, pendingTransfer: pendingTransfer)
                    }
                    ForEach(actions.prefix(2), id: \.title) { action in
                        WidgetActionChip(action: action)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isCompact ? 5 : 6)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .widgetAccentable(false)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(color(for: host.status).opacity(host.status == .offline ? 0.55 : 0.9))
                .frame(width: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 8,
                    bottomLeadingRadius: 8,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                ))
        }
        .overlay {
            ZStack {
                if let samples = host.diagnostics?.ping?.samples {
                    PingSparklineView(samples: samples)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .opacity(0.11)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .allowsHitTesting(false)
                }
                if wormholeContact != nil {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(pendingTransfer == nil ? 0.62 : 0.95), lineWidth: pendingTransfer == nil ? 1.25 : 2)
                }
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

private struct WidgetWormholeChip: View {
    let mode: TailOpsWormholeOpenRequest.Mode
    let contact: TailOpsWormholeContact
    var pendingTransfer: TailOpsWormholePendingTransfer?
    var showsTitle = false

    var body: some View {
        Button(intent: OpenTailOpsWormholeIntent(
            mode: mode,
            contactID: contact.id,
            pendingTransferID: mode == .receive ? pendingTransfer?.id : nil
        )) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .frame(width: 18, height: 18)
                if showsTitle {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(height: 22)
            .padding(.horizontal, showsTitle ? 7 : 2)
            .background(Color.accentColor.opacity(pendingTransfer == nil ? 0.14 : 0.28), in: Capsule())
            .widgetAccentable(false)
            .accessibilityLabel("\(title) with \(contact.displayName)")
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        switch mode {
        case .send:
            return "Send"
        case .receive:
            return "Receive"
        }
    }

    private var systemImage: String {
        switch mode {
        case .send:
            return "paperplane"
        case .receive:
            return "tray.and.arrow.down"
        }
    }
}

private extension [TailOpsWormholePendingTransfer] {
    func pendingTransfer(for contact: TailOpsWormholeContact?) -> TailOpsWormholePendingTransfer? {
        guard let contact else { return nil }
        return first {
            !$0.isExpired()
                && ($0.contactID == contact.id || $0.pairingID == contact.pairingID)
                && $0.direction == .incoming
        }
    }

    static var previewBen: [TailOpsWormholePendingTransfer] {
        [
            TailOpsWormholePendingTransfer(
                contactID: "ben",
                pairingID: "monroe-ben",
                senderName: "Monroe",
                fileName: "prompt.md",
                fileSizeBytes: 2048,
                direction: .incoming,
                expiresAt: Date().addingTimeInterval(900)
            )
        ]
    }
}

private extension TailOpsWormholeConfiguration {
    func contact(for host: TailnetHost) -> TailOpsWormholeContact? {
        contacts.first { $0.tailnetNodeID == host.id }
    }

    static var previewBen: TailOpsWormholeConfiguration {
        TailOpsWormholeConfiguration(contacts: [
            TailOpsWormholeContact(
                id: "ben",
                displayName: "Ben",
                pairingID: "monroe-ben",
                tailnetNodeID: "peer-ben"
            )
        ])
    }
}

private struct WidgetActionChip: View {
    let action: HostAction
    var showsTitle = false

    var body: some View {
        if action.kind == .ssh, let value = action.value {
            Button(intent: OpenSSHInTerminalIntent(host: value)) {
                chipContent
            }
            .buttonStyle(.plain)
        } else if action.kind == .dashboard, let url = action.url {
            Button(intent: OpenDashboardURLIntent(url: url)) {
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
        HStack(spacing: 4) {
            chipIcon
                .frame(width: 18, height: 18)
            if showsTitle {
                Text(action.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.primary.opacity(0.8))
        .frame(height: 22)
        .padding(.horizontal, showsTitle ? 7 : 2)
        .background(Color.primary.opacity(0.1), in: Capsule())
        .widgetAccentable(false)
        .accessibilityLabel(action.title)
    }

    @ViewBuilder
    private var chipIcon: some View {
        if let emoji = action.emoji,
           !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(emoji)
                .font(.caption2)
        } else {
            Image(systemName: systemImage)
        }
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
    TailOpsWidgetView(entry: TailOpsEntry(
        date: .now,
        snapshot: .preview,
        actionConfiguration: .preview,
        refreshHealth: TailOpsRefreshHealth(lastSuccessAt: .now),
        wormholeConfiguration: .previewBen,
        pendingWormholeTransfers: .previewBen
    ))
        .frame(width: 340, height: 240)
}

#Preview("Small", as: .systemSmall) {
    TailOpsWidget()
} timeline: {
    TailOpsEntry(date: .now, snapshot: .preview, actionConfiguration: .preview, refreshHealth: TailOpsRefreshHealth(lastSuccessAt: .now), wormholeConfiguration: .previewBen, pendingWormholeTransfers: .previewBen)
}

#Preview("Medium", as: .systemMedium) {
    TailOpsWidget()
} timeline: {
    TailOpsEntry(date: .now, snapshot: .preview, actionConfiguration: .preview, refreshHealth: TailOpsRefreshHealth(lastSuccessAt: .now), wormholeConfiguration: .previewBen, pendingWormholeTransfers: .previewBen)
}

#Preview("Large", as: .systemLarge) {
    TailOpsWidget()
} timeline: {
    TailOpsEntry(date: .now, snapshot: .preview, actionConfiguration: .preview, refreshHealth: TailOpsRefreshHealth(lastSuccessAt: .now), wormholeConfiguration: .previewBen, pendingWormholeTransfers: .previewBen)
}
#endif
