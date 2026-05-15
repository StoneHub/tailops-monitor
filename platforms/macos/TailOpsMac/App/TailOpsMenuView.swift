import AppKit
import SwiftUI
import TailOpsCore
import TailOpsShared
import UniformTypeIdentifiers

struct TailOpsMenuView: View {
    @ObservedObject var monitor: TailnetMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summaryRow

            Divider()

            if monitor.snapshot.hosts.isEmpty {
                Text("No tailnet hosts loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(monitor.snapshot.hosts) { host in
                            HostRow(host: host, actions: monitor.actions(for: host))
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(height: hostListHeight)
            }

            if let lastError = monitor.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(14)
    }

    private var hostListHeight: CGFloat {
        let visibleRows = min(max(monitor.snapshot.hosts.count, 1), 4)
        return CGFloat(visibleRows) * 86
    }

    private var header: some View {
        HStack {
            TailOpsConstellationIcon(trafficLight: monitor.summary.trafficLight)
                .frame(width: 22, height: 22)
            Text("TailOps")
                .font(.headline)

            Spacer()

            Button {
                Task { await monitor.refresh() }
            } label: {
                Image(systemName: monitor.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh tailnet")
            .disabled(monitor.isRefreshing)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            StatusPill(title: "Online", value: monitor.summary.onlineCount, color: .green)
            StatusPill(title: "Warn", value: monitor.summary.warningCount, color: .orange)
            StatusPill(title: "Offline", value: monitor.summary.offlineCount, color: .red)
        }
    }
}

#if DEBUG
#Preview("Menu Panel") {
    TailOpsMenuView(
        monitor: TailnetMonitor(
            statusProvider: PreviewStatusProvider(),
            pingProvider: nil,
            snapshotStore: PreviewSnapshotStore(),
            initialSnapshot: .preview
        )
    )
    .frame(width: 360)
}

private struct PreviewStatusProvider: TailscaleStatusProviding {
    func statusJSON() async throws -> Data {
        Data()
    }
}

private struct PreviewSnapshotStore: SharedSnapshotStoring {
    func load() throws -> TailnetSnapshot? {
        .preview
    }

    func save(_ snapshot: TailnetSnapshot) throws {}

    func loadActionConfiguration() throws -> TailnetActionConfiguration? {
        .preview
    }

    func saveActionConfiguration(_ configuration: TailnetActionConfiguration) throws {}

    func loadAppPreferences() throws -> TailOpsAppPreferences? {
        TailOpsAppPreferences()
    }

    func saveAppPreferences(_ preferences: TailOpsAppPreferences) throws {}

    func loadSettingsOpenRequest() throws -> TailOpsSettingsOpenRequest? { nil }
    func saveSettingsOpenRequest(_ request: TailOpsSettingsOpenRequest) throws {}
    func clearSettingsOpenRequest() throws {}
}
#endif

private struct StatusPill: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(value.formatted())
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HostRow: View {
    let host: TailnetHost
    let actions: [HostAction]
    @State private var isDropTargeted = false
    @State private var transferState: TaildropTransferState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.callout.weight(.semibold))
                    Text(host.magicDNSName ?? host.primaryAddress ?? "No Tailscale address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(availabilityText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let pingText {
                        Text(pingText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(host.operatingSystem ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    transferIndicator
                }
            }

            HStack(spacing: 6) {
                ForEach(actions, id: \.title) { action in
                    Button {
                        perform(action)
                    } label: {
                        HStack(spacing: 3) {
                            Text(action.emoji ?? fallbackEmoji(for: action))
                            Text(action.title)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                if let samples = host.diagnostics?.ping?.samples {
                    PingSparklineView(samples: samples)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .opacity(0.34)
                }
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.22) : Color.clear)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTargeted ? Color.accentColor.opacity(0.75) : Color.clear, lineWidth: 1.5)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleFileDrop(providers)
        }
    }

    private var statusColor: Color {
        switch host.status {
        case .online:
            return .green
        case .warning:
            return .orange
        case .offline:
            return .red
        }
    }

    private var availabilityText: String {
        switch host.status {
        case .online:
            return host.role == .thisDevice ? "This device" : "Available now"
        case .warning:
            return "Needs attention"
        case .offline:
            guard let lastSeen = host.lastSeen else {
                return "No recent connection"
            }
            return "Last seen \(lastSeen.formatted(.relative(presentation: .named)))"
        }
    }

    @ViewBuilder
    private var transferIndicator: some View {
        switch transferState {
        case .idle:
            EmptyView()
        case .sending:
            ProgressView()
                .controlSize(.mini)
        case .sent:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }

    private var pingText: String? {
        guard let ping = host.diagnostics?.ping,
              let latency = ping.latestLatencyMilliseconds
        else {
            return nil
        }

        let latestText = latency.formatted(.number.precision(.fractionLength(0...1)))
        guard let average = ping.averageLatencyMilliseconds else {
            return "\(ping.latestRoute.label) \(latestText) ms"
        }

        let averageText = average.formatted(.number.precision(.fractionLength(0...1)))
        return "\(ping.latestRoute.label) \(latestText) ms | avg \(averageText) ms over \(ping.samples.count)"
    }

    private func perform(_ action: HostAction) {
        switch action.kind {
        case .ssh, .dashboard:
            if let url = action.url {
                openAndActivate(url)
            }
        case .copyAddress:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(action.value ?? "", forType: .string)
        }
    }

    private func fallbackEmoji(for action: HostAction) -> String {
        switch action.kind {
        case .ssh:
            return ">"
        case .dashboard:
            return "*"
        case .copyAddress:
            return "#"
        }
    }

    private func openAndActivate(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open(url, configuration: configuration) { application, _ in
            application?.activate(options: [.activateAllWindows])
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let fileURL = taildropFileURL(from: item) else { return }

            Task { @MainActor in
                transferState = .sending
                do {
                    try await ProcessTaildropFileTransferProvider().send(fileURL: fileURL, to: host)
                    transferState = .sent
                } catch {
                    transferState = .failed
                }

                try? await Task.sleep(for: .seconds(2))
                transferState = .idle
            }
        }

        return true
    }
}

private enum TaildropTransferState {
    case idle
    case sending
    case sent
    case failed
}

private nonisolated func taildropFileURL(from item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
        return url
    }
    if let data = item as? Data {
        return URL(dataRepresentation: data, relativeTo: nil)
    }
    if let string = item as? String {
        return URL(string: string)
    }
    return nil
}
