import AppKit
import SwiftUI
import TailOpsCore
import TailOpsShared

struct TailOpsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: TailOpsActionSettingsModel
    @StateObject private var preferencesModel: TailOpsPreferencesModel
    @State private var importExportText = ""
    @State private var showsJSONEditor = false
    @State private var selectedSection: SettingsSection = .general
    @State private var selectedHostID: EditableHostActions.ID?

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case hostActions = "Host Actions"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .general:
                return "gearshape"
            case .hostActions:
                return "terminal"
            }
        }
    }

    init(
        model: TailOpsActionSettingsModel = TailOpsActionSettingsModel(),
        preferencesModel: TailOpsPreferencesModel = TailOpsPreferencesModel()
    ) {
        _model = StateObject(wrappedValue: model)
        _preferencesModel = StateObject(wrappedValue: preferencesModel)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            switch selectedSection {
            case .general:
                generalContent
            case .hostActions:
                hostActionsContent
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(TailOpsWindowBackground())
        .onAppear {
            if selectedHostID == nil {
                selectedHostID = model.hostActions.first?.id
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("TailOps")
                    .font(.headline.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)

            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.rawValue, systemImage: section.systemImage)
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            selectedSection == section ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            if selectedSection == section {
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("Native widget controls")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
        }
        .padding(14)
        .frame(width: 164)
        .background(.ultraThinMaterial)
    }

    private var generalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                contentHeader(
                    title: "General",
                    subtitle: "Choose how TailOps stays available on this Mac."
                )
                appControls

                VStack(alignment: .leading, spacing: 10) {
                    Label("Widget-first by design", systemImage: "rectangle.3.group")
                        .font(.headline)
                    Text("The hidden host app refreshes shared tailnet state and services widget actions. Settings and Wormhole open only when requested.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .tailOpsGlassPanel(tint: .blue)

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { preferencesModel.launchAtLogin },
                    set: { preferencesModel.setLaunchAtLogin($0) }
                )
            )
            .padding(.vertical, 12)

            Text("TailOps remains widget-first; the host app stays out of the way while it refreshes shared state and handles actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .tailOpsGlassPanel(tint: .blue)
    }

    private var hostActionsContent: some View {
        HStack(spacing: 0) {
            hostList

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                contentHeader(
                    title: "Host Actions",
                    subtitle: "Choose the actions exposed by this host in the widget."
                )

                if let hostBinding = selectedHostBinding {
                    ScrollView {
                        HostActionsEditor(
                            hostActions: hostBinding,
                            addDashboard: { model.addDashboard(to: hostBinding.wrappedValue.id, target: $0) },
                            addAction: { model.addAction(to: hostBinding.wrappedValue.id) },
                            removeAction: { model.removeAction($0, from: hostBinding.wrappedValue.id) },
                            removeHost: { removeSelectedHost(hostBinding.wrappedValue.id) }
                        )
                        .padding(.vertical, 2)
                    }
                } else {
                    ContentUnavailableView(
                        "No hosts",
                        systemImage: "network.slash",
                        description: Text("Add a host to configure widget actions.")
                    )
                }

                validationPanel

                if showsJSONEditor {
                    jsonEditor
                }

                footer
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var hostList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hosts on Your Tailnet")
                        .font(.headline)
                    Text("\(model.hostActions.count) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.addHostActions()
                    selectedHostID = model.hostActions.last?.id
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add custom host")
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.hostActions) { host in
                        HostSelectionRow(
                            host: host,
                            isSelected: host.id == selectedHostBinding?.wrappedValue.id
                        ) {
                            selectedHostID = host.id
                        }
                    }
                }
            }

            HStack {
                Button {
                    model.addHostActions()
                    selectedHostID = model.hostActions.last?.id
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    importExportText = model.exportJSON()
                    showsJSONEditor = true
                } label: {
                    Label("JSON", systemImage: "curlybraces")
                }
                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 252)
        .background(.thinMaterial)
    }

    private func contentHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedHostBinding: Binding<EditableHostActions>? {
        guard !model.hostActions.isEmpty else { return nil }
        let resolvedID = selectedHostID ?? model.hostActions.first?.id
        guard let index = model.hostActions.firstIndex(where: { $0.id == resolvedID }) else {
            return Binding(
                get: { model.hostActions[0] },
                set: { model.hostActions[0] = $0 }
            )
        }
        return Binding(
            get: { model.hostActions[index] },
            set: { model.hostActions[index] = $0 }
        )
    }

    private func removeSelectedHost(_ id: EditableHostActions.ID) {
        model.removeHostActions(id: id)
        selectedHostID = model.hostActions.first?.id
    }

    @ViewBuilder
    private var validationPanel: some View {
        if !model.validationIssues.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(model.validationIssues.map(\.message), id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var jsonEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Import / Export JSON")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("Import") {
                    model.importJSON(importExportText)
                }
                Button("Close") {
                    showsJSONEditor = false
                }
            }

            TextEditor(text: $importExportText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 150)
                .scrollContentBackground(.hidden)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var footer: some View {
        HStack {
            if let preferenceError = preferencesModel.saveError {
                Text(preferenceError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let saveError = model.saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let preferenceMessage = preferencesModel.statusMessage {
                Text(preferenceMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let importExportMessage = model.importExportMessage {
                Text(importExportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Kinds: URL opens dashboards, SSH opens ssh:// links, Copy puts configured values on the clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Save") {
                if model.save() {
                    dismiss()
                    NSApp.keyWindow?.close()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSave)
        }
    }
}

private struct HostSelectionRow: View {
    let host: EditableHostActions
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(statusColor.opacity(0.16))
                        .frame(width: 34, height: 30)
                    Image(systemName: host.isKnownHost ? "desktopcomputer" : "network")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(host.displayName ?? (host.hostID.isEmpty ? "New Host" : host.hostID))
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(host.displayDetail ?? (host.hostID.isEmpty ? "Custom host" : host.hostID))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.32) : Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch host.status {
        case .online:
            return .green
        case .warning:
            return .orange
        case .offline:
            return .red
        case nil:
            return .secondary
        }
    }
}

private struct HostActionsEditor: View {
    @Binding var hostActions: EditableHostActions
    let addDashboard: (String) -> Void
    let addAction: () -> Void
    let removeAction: (EditableQuickAction.ID) -> Void
    let removeHost: () -> Void
    @State private var dashboardTarget = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            hostHeader
            dashboardEntry

            VStack(spacing: 8) {
                ForEach($hostActions.actions) { $action in
                    ActionEditorRow(action: $action) {
                        removeAction(action.id)
                    }
                }
            }
        }
        .padding(16)
        .tailOpsGlassPanel(tint: .blue)
    }

    private var hostHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(hostActions.displayName ?? hostActions.hostID)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let detail = hostActions.displayDetail ?? (hostActions.isKnownHost ? nil : hostActions.hostID) {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !hostActions.isKnownHost {
                Button(role: .destructive) {
                    removeHost()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove custom host")
            }
        }
    }

    private var dashboardEntry: some View {
        HStack(spacing: 8) {
            TextField("Paste dashboard address, like http://host:8080", text: $dashboardTarget)
                .textFieldStyle(.roundedBorder)
            Button {
                addDashboard(dashboardTarget)
                dashboardTarget = ""
            } label: {
                Label("Add", systemImage: "plus")
            }
            .disabled(dashboardTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button {
                addAction()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Add custom action")
        }
    }

    private var statusColor: Color {
        switch hostActions.status {
        case .online:
            return .green
        case .warning:
            return .orange
        case .offline:
            return .secondary
        case nil:
            return .secondary
        }
    }
}

private struct ActionEditorRow: View {
    @Binding var action: EditableQuickAction
    let remove: () -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
            GridRow {
                Text("Icon")
                Text("Title")
                Text("Kind")
                Text("Target")
                Text("")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            GridRow {
                TextField("🧭", text: $action.emoji)
                    .frame(width: 48)

                TextField("Dash", text: $action.title)
                    .frame(minWidth: 96)

                Picker("Kind", selection: $action.kind) {
                    Text("URL").tag(TailnetQuickAction.Kind.url)
                    Text("SSH").tag(TailnetQuickAction.Kind.ssh)
                    Text("Copy").tag(TailnetQuickAction.Kind.copy)
                }
                .labelsHidden()
                .frame(width: 92)

                TextField(targetPlaceholder, text: $action.target)
                    .frame(minWidth: 190)

                Button(role: .destructive) {
                    remove()
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove action")
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private var targetPlaceholder: String {
        switch action.kind {
        case .url:
            return "http://host.tailnet.ts.net:8080"
        case .ssh:
            return "host.tailnet.ts.net"
        case .copy:
            return "100.x.y.z"
        }
    }
}

struct TailOpsWindowBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.09),
                    Color.cyan.opacity(0.035),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct TailOpsGlassPanelModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(
                tint.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.36), tint.opacity(0.18), Color.primary.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.08), radius: 12, y: 5)
    }
}

extension View {
    func tailOpsGlassPanel(tint: Color = .blue) -> some View {
        modifier(TailOpsGlassPanelModifier(tint: tint))
    }
}

#if DEBUG
#Preview("Settings") {
    let store = InMemoryTailOpsStore(
        snapshot: .preview,
        actionConfiguration: .preview,
        appPreferences: TailOpsAppPreferences()
    )
    TailOpsSettingsView(
        model: TailOpsActionSettingsModel(
            tailnetStore: store,
            settingsStore: store,
            configuration: .preview
        ),
        preferencesModel: TailOpsPreferencesModel(settingsStore: store)
    )
}
#endif
