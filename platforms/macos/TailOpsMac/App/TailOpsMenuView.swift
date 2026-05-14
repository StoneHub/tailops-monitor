import AppKit
import SwiftUI
import TailOpsCore
import TailOpsShared

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
        return CGFloat(visibleRows) * 72
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
                }
                Spacer()
                Text(host.operatingSystem ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(actions, id: \.title) { action in
                    Button(action.title) {
                        perform(action)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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

    private func perform(_ action: HostAction) {
        switch action.kind {
        case .ssh, .dashboard:
            if let url = action.url {
                NSWorkspace.shared.open(url)
            }
        case .copyAddress:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(action.value ?? "", forType: .string)
        }
    }
}
