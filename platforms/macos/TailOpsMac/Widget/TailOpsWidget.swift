import SwiftUI
import TailOpsCore
import TailOpsIntents
import TailOpsShared
import WidgetKit

struct TailOpsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TailOpsWidgetKind.identifier, provider: TailOpsTimelineProvider()) { entry in
            TailOpsWidgetEntryView(entry: entry)
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

    func at(_ date: Date) -> TailOpsEntry {
        TailOpsEntry(
            date: date,
            snapshot: snapshot,
            actionConfiguration: actionConfiguration,
            refreshHealth: refreshHealth,
            wormholeConfiguration: wormholeConfiguration,
            pendingWormholeTransfers: pendingWormholeTransfers
        )
    }
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

    /// The host app reloads timelines after every refresh, so the widget does not
    /// poll. It only adds entries for moments its own display changes: the
    /// snapshot going stale, a stuck refresh timing out, or a pending transfer
    /// expiring.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TailOpsEntry>) -> Void) {
        let entry = entry()
        let dates = TailOpsWidgetSchedule.entryDates(
            now: entry.date,
            snapshotGeneratedAt: entry.snapshot.hosts.isEmpty ? nil : entry.snapshot.generatedAt,
            refreshHealth: entry.refreshHealth,
            pendingTransferExpiries: entry.pendingWormholeTransfers.map(\.expiresAt)
        )
        let entries = dates.map { entry.at($0) }
        let safetyReload = entry.date.addingTimeInterval(TailOpsWidgetSchedule.safetyReloadInterval)
        completion(Timeline(entries: entries, policy: .after(safetyReload)))
    }

    private func entry() -> TailOpsEntry {
        let store = SharedSnapshotStore()
        return TailOpsEntry(
            date: Date(),
            snapshot: (try? store.load()) ?? TailnetSnapshot(hosts: []),
            actionConfiguration: (try? store.loadActionConfiguration()) ?? TailnetActionConfiguration(),
            refreshHealth: ((try? store.loadRefreshHealth()) ?? TailOpsRefreshHealth())
                .including(try? store.loadRefreshRequest()),
            wormholeConfiguration: (try? store.loadWormholeConfiguration()) ?? TailOpsWormholeConfiguration(),
            pendingWormholeTransfers: (try? store.loadWormholePendingTransfers()) ?? []
        )
    }
}

private struct TailOpsWidgetEntryView: View {
    let entry: TailOpsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        TailOpsWidgetView(entry: entry, family: family)
    }
}

struct TailOpsWidgetView: View {
    let entry: TailOpsEntry
    let family: WidgetFamily

    private var actionCatalog: HostActionCatalog {
        HostActionCatalog(configuration: entry.actionConfiguration)
    }

    private var layout: TailnetWidgetHostLayout {
        TailnetWidgetHostLayout(hosts: entry.snapshot.hosts, limit: visibleHostLimit)
    }

    private var gridHosts: [TailnetHost] {
        Array(entry.snapshot.hosts.sorted(by: gridSort).prefix(gridHostLimit))
    }

    private var hiddenGridOfflineCount: Int {
        let shownIDs = Set(gridHosts.map(\.id))
        return entry.snapshot.hosts.filter { $0.status == .offline && !shownIDs.contains($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            WidgetChromeHeader(symbol: symbol, title: "TailOps") {
                HStack(spacing: 7) {
                    Button(intent: OpenTailscaleAppIntent()) {
                        WidgetChromePill {
                            Label("Tailscale", systemImage: "arrow.up.forward.app")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    Button(intent: RefreshTailOpsWidgetIntent()) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh TailOps")
                    WidgetSnapshotFreshness(
                        generatedAt: entry.snapshot.generatedAt,
                        refreshHealth: entry.refreshHealth,
                        referenceDate: entry.date,
                        hasSnapshot: !entry.snapshot.hosts.isEmpty
                    )
                    Link(destination: TailOpsSettingsOpenSignal.url) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Open TailOps Settings")
                }
                .buttonStyle(.plain)
            }

            if let banner {
                WidgetStatusBanner(banner: banner)
            }

            if entry.snapshot.hosts.isEmpty {
                WidgetEmptyState()
            } else if usesStatusGrid {
                WidgetHostStatusGrid(
                    hosts: gridHosts,
                    actionCatalog: actionCatalog,
                    wormholeConfiguration: entry.wormholeConfiguration,
                    pendingTransfers: entry.pendingWormholeTransfers,
                    referenceDate: entry.date,
                    style: gridStyle
                )
                if hiddenGridOfflineCount > 0 {
                    WidgetOfflineSummary(count: hiddenGridOfflineCount)
                }
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(layout.visibleHosts) { host in
                        WidgetHostActionRow(
                            host: host,
                            actions: actionCatalog.actions(for: host),
                            wormholeContact: entry.wormholeConfiguration.contact(for: host),
                            pendingTransfer: entry.pendingWormholeTransfers.pendingTransfer(
                                for: entry.wormholeConfiguration.contact(for: host),
                                at: entry.date
                            ),
                            isCompact: usesCompactRows,
                            showsActionTitles: family == .systemMedium
                        )
                    }
                    // The banner takes this line's space in the medium family.
                    if layout.hiddenOfflineCount > 0, banner == nil {
                        WidgetOfflineSummary(count: layout.hiddenOfflineCount)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .widgetChromeSurface()
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    private var symbol: String {
        "point.3.connected.trianglepath.dotted"
    }

    /// The single most important tailnet-wide message, if any.
    private var banner: WidgetStatusBanner.Content? {
        if entry.refreshHealth.hasFailedSinceLastSuccess, let error = entry.refreshHealth.lastError {
            return .init(symbol: "exclamationmark.triangle.fill", text: error, tone: .problem)
        }
        guard let health = entry.snapshot.health else { return nil }
        if let problem = health.backendProblem {
            return .init(symbol: "power", text: problem, tone: .problem)
        }
        if let warning = health.warnings.first {
            let more = health.warnings.count > 1 ? " (+\(health.warnings.count - 1) more)" : ""
            return .init(symbol: "exclamationmark.triangle", text: warning + more, tone: .warning)
        }
        if let exitNode = health.exitNode {
            return .init(symbol: "arrow.up.right.circle", text: "Exit node: \(exitNode.displayName)", tone: .info)
        }
        return nil
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
        family == .systemExtraLarge ? 4 : 2
    }

    private var gridHostLimit: Int {
        switch family {
        case .systemExtraLarge:
            return 9
        case .systemLarge:
            // Two rows of tiles; three do not fit a large widget's height.
            return 4
        default:
            return visibleHostLimit
        }
    }

    private var gridColumnCount: Int {
        switch family {
        case .systemExtraLarge:
            return 3
        case .systemLarge:
            return 2
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
                maximumTitledChips: 3
            )
        default:
            return WidgetHostStatusGrid.Style(
                columns: gridColumnCount,
                columnSpacing: 10,
                rowSpacing: 10,
                tileMinHeight: 84,
                tileMaxHeight: nil,
                tileHorizontalPadding: 10,
                tileVerticalPadding: 8,
                tileContentSpacing: 7,
                maximumTitledChips: 2
            )
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
        14
    }

    private var verticalPadding: CGFloat {
        switch family {
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

    var body: some View {
        HStack(spacing: 3) {
            if refreshHealth.hasFailedSinceLastSuccess {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Failed")
            } else if isRefreshActive {
                ProgressView()
                    .controlSize(.mini)
                Text("Refreshing")
            } else if hasTimedOut {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Timed out")
            } else if isStale {
                Image(systemName: "clock.badge.exclamationmark")
                Text("Stale")
            }

            if hasSnapshot {
                if showsStateLabel {
                    Text("·")
                }
                Text(generatedAt, style: .relative)
                    .id(generatedAt)
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
        hasSnapshot && referenceDate.timeIntervalSince(generatedAt) >= TailOpsWidgetSchedule.staleInterval
    }

    private var showsStateLabel: Bool {
        refreshHealth.hasFailedSinceLastSuccess || isRefreshActive || hasTimedOut || isStale
    }

    private var showsWarning: Bool {
        refreshHealth.hasFailedSinceLastSuccess || hasTimedOut || isStale
    }

    private var isRefreshActive: Bool {
        refreshHealth.isRefreshInProgress(at: referenceDate, timeout: TailOpsWidgetSchedule.refreshTimeout)
    }

    private var hasTimedOut: Bool {
        refreshHealth.hasTimedOut(at: referenceDate, timeout: TailOpsWidgetSchedule.refreshTimeout)
    }

    private var accessibilityText: String {
        let age = hasSnapshot
            ? "Snapshot generated " + RelativeDateTimeFormatter().localizedString(for: generatedAt, relativeTo: referenceDate)
            : "No tailnet snapshot available"
        if refreshHealth.hasFailedSinceLastSuccess {
            return "Refresh failed. \(age)"
        }
        if isRefreshActive {
            return "Refreshing. \(age)"
        }
        if hasTimedOut {
            return "Refresh timed out. \(age)"
        }
        if isStale {
            return "Snapshot stale. \(age)"
        }
        return age
    }
}

private struct WidgetStatusBanner: View {
    struct Content {
        enum Tone {
            case problem
            case warning
            case info
        }

        let symbol: String
        let text: String
        let tone: Tone
    }

    let banner: Content

    var body: some View {
        Label {
            Text(banner.text)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: banner.symbol)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch banner.tone {
        case .problem:
            return .red
        case .warning:
            return .orange
        case .info:
            return .secondary
        }
    }
}

private extension TailnetHost {
    /// Idle peers have no live path worth naming; Tailscale connects on demand.
    var activeRouteLabel: String? {
        guard let connection, connection != .idle else { return nil }
        return connection.label
    }

    /// Replaces the address line while a key-expiry warning is active.
    var keyExpiryText: String? {
        guard status == .warning, let keyExpiry,
              keyExpiry.timeIntervalSinceNow < TailnetHost.keyExpiryWarningInterval
        else { return nil }
        return "Key expires \(keyExpiry.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// What needs attention on this host: a node health warning first, then key expiry.
    var attentionText: String? {
        if let health, !health.activeWarnings.isEmpty {
            return health.summaryText
        }
        return keyExpiryText
    }

    var hasHealthWarnings: Bool {
        !(health?.activeWarnings.isEmpty ?? true)
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

private struct WidgetOfflineSummary: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            WidgetHostStatusMarker(status: .offline, style: .inline)
            Text("\(count) offline")
            Spacer()
        }
        .widgetChromeFootnote()
        .padding(.top, 1)
    }
}

/// Status by symbol as well as color: Clear and Tinted widget styles render
/// every color white, so the shape has to carry the meaning on its own.
private struct WidgetHostStatusMarker: View {
    enum Style {
        /// A symbol on a soft circle, for grid tiles.
        case badge
        /// A bare symbol sized to sit beside a line of text.
        case inline
    }

    let status: TailnetHost.Status
    let style: Style

    var body: some View {
        switch style {
        case .badge:
            ZStack {
                Circle()
                    .fill(status.widgetColor.opacity(status == .offline ? 0.18 : 0.26))
                    .frame(width: 18, height: 18)
                symbol
            }
            .widgetAccentable()
        case .inline:
            symbol
                .widgetAccentable()
        }
    }

    private var symbol: some View {
        Image(systemName: status.widgetSymbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status.widgetColor)
    }
}

private extension TailnetHost.Status {
    var widgetColor: Color {
        switch self {
        case .online:
            return .green
        case .warning:
            return .orange
        case .offline:
            return .secondary
        }
    }

    var widgetSymbol: String {
        switch self {
        case .online:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .offline:
            return "minus.circle.fill"
        }
    }
}

private struct WidgetHostStatusGrid: View {
    let hosts: [TailnetHost]
    let actionCatalog: HostActionCatalog
    let wormholeConfiguration: TailOpsWormholeConfiguration
    let pendingTransfers: [TailOpsWormholePendingTransfer]
    let referenceDate: Date
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
        /// Chips drop their titles when more than this many share a tile's width.
        let maximumTitledChips: Int
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
                    pendingTransfer: pendingTransfers.pendingTransfer(
                        for: wormholeConfiguration.contact(for: host),
                        at: referenceDate
                    ),
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
                WidgetHostStatusMarker(status: host.status, style: .badge)

                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    HStack(spacing: 5) {
                        Text(statusText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(host.status.widgetColor)
                            .lineLimit(1)

                        if let route = host.activeRouteLabel {
                            Text(route)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

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
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            if host.status != .offline || pendingTransfer != nil {
                HStack(spacing: 5) {
                    if let wormholeContact {
                        WidgetWormholeChip(mode: .send, contact: wormholeContact, showsTitle: showsChipTitles)
                        WidgetWormholeChip(
                            mode: .receive,
                            contact: wormholeContact,
                            pendingTransfer: pendingTransfer,
                            showsTitle: showsChipTitles
                        )
                    }
                    ForEach(Array(visibleActions.enumerated()), id: \.offset) { _, action in
                        WidgetActionChip(action: action, showsTitle: showsChipTitles)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        // The grid otherwise proposes a short row height and shrinks the host name to fit.
        .fixedSize(horizontal: false, vertical: true)
        .frame(
            maxWidth: .infinity,
            minHeight: style.tileMinHeight,
            maxHeight: style.tileMaxHeight,
            alignment: .topLeading
        )
        .padding(.horizontal, style.tileHorizontalPadding)
        .padding(.vertical, style.tileVerticalPadding)
        .widgetChromeTile(highlighted: pendingTransfer != nil)
    }

    private var detailText: String {
        host.attentionText ?? host.health?.summaryText ?? host.primaryAddress ?? host.magicDNSName
            ?? host.operatingSystem ?? "No address"
    }

    private var visibleActions: ArraySlice<HostAction> {
        actions.prefix(3)
    }

    private var showsChipTitles: Bool {
        let chipCount = visibleActions.count + (wormholeContact == nil ? 0 : 2)
        return chipCount <= style.maximumTitledChips
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
            if host.hasHealthWarnings { return "Attention" }
            return host.keyExpiryText == nil ? "Warning" : "Key expiring"
        case .offline:
            return "Offline"
        }
    }
}

private struct WidgetHostActionRow: View {
    let host: TailnetHost
    let actions: [HostAction]
    let wormholeContact: TailOpsWormholeContact?
    let pendingTransfer: TailOpsWormholePendingTransfer?
    let isCompact: Bool
    let showsActionTitles: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    WidgetHostStatusMarker(status: host.status, style: .inline)
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
                        .foregroundStyle(.tint)
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

            HStack(spacing: 4) {
                if let wormholeContact {
                    WidgetWormholeChip(mode: .send, contact: wormholeContact, showsTitle: showsChipTitles)
                    WidgetWormholeChip(
                        mode: .receive,
                        contact: wormholeContact,
                        pendingTransfer: pendingTransfer,
                        showsTitle: showsChipTitles
                    )
                }
                ForEach(Array(visibleActions.enumerated()), id: \.offset) { _, action in
                    WidgetActionChip(action: action, showsTitle: showsChipTitles)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isCompact ? 5 : 6)
        .overlay {
            if let samples = host.diagnostics?.ping?.samples {
                PingSparklineView(samples: samples)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .opacity(0.11)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .widgetChromeTile(cornerRadius: 11, highlighted: pendingTransfer != nil)
    }

    private var visibleActions: ArraySlice<HostAction> {
        actions.prefix(2)
    }

    /// A row has room for two titled chips; more squeeze the titles out.
    private var showsChipTitles: Bool {
        let chipCount = visibleActions.count + (wormholeContact == nil ? 0 : 2)
        return showsActionTitles && chipCount <= 2
    }

    private var detailText: String {
        if let attentionText = host.attentionText {
            return attentionText
        }
        let address = host.primaryAddress ?? host.magicDNSName ?? host.status.rawValue
        guard let route = host.activeRouteLabel else { return address }
        return "\(address) · \(route)"
    }

    private var pingText: String? {
        guard let latest = host.diagnostics?.ping?.latestLatencyMilliseconds else {
            return nil
        }

        return "\(latest.formatted(.number.precision(.fractionLength(0...0)))) ms"
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
            WidgetChromePill(prominence: pendingTransfer == nil ? .tinted : .selected, iconOnly: !showsTitle) {
                HStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .frame(width: 18, height: 18)
                    if showsTitle {
                        Text(title)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
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
    /// Uses the entry's date, not the clock: WidgetKit renders future entries ahead of time.
    func pendingTransfer(for contact: TailOpsWormholeContact?, at date: Date) -> TailOpsWormholePendingTransfer? {
        guard let contact else { return nil }
        return first {
            !$0.isExpired(at: date)
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
        } else if [.dashboard, .screenSharing, .fileSharing].contains(action.kind), let url = action.url {
            Button(intent: OpenDashboardURLIntent(url: url)) {
                chipContent
            }
            .buttonStyle(.plain)
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
        WidgetChromePill(iconOnly: !showsTitle) {
            HStack(spacing: 4) {
                chipIcon
                    .frame(width: 18, height: 18)
                if showsTitle {
                    Text(action.title)
                        .minimumScaleFactor(0.75)
                }
            }
        }
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
        case .screenSharing:
            return "rectangle.on.rectangle"
        case .fileSharing:
            return "folder"
        case .copyAddress:
            return "doc.on.doc"
        }
    }
}

#if DEBUG
#Preview("Widget View") {
    TailOpsWidgetView(
        entry: TailOpsEntry(
            date: .now,
            snapshot: .preview,
            actionConfiguration: .preview,
            refreshHealth: TailOpsRefreshHealth(lastSuccessAt: .now),
            wormholeConfiguration: .previewBen,
            pendingWormholeTransfers: .previewBen
        ),
        family: .systemMedium
    )
        .frame(width: 340, height: 240)
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
