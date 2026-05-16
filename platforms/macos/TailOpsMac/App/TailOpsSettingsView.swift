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

    init(
        model: TailOpsActionSettingsModel = TailOpsActionSettingsModel(),
        preferencesModel: TailOpsPreferencesModel = TailOpsPreferencesModel()
    ) {
        _model = StateObject(wrappedValue: model)
        _preferencesModel = StateObject(wrappedValue: preferencesModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            appControls

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach($model.hostActions) { $hostActions in
                        HostActionsEditor(
                            hostActions: $hostActions,
                            addDashboard: { model.addDashboard(to: hostActions.id, target: $0) },
                            addAction: { model.addAction(to: hostActions.id) },
                            removeAction: { model.removeAction($0, from: hostActions.id) },
                            removeHost: { model.removeHostActions(id: hostActions.id) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            validationPanel

            if showsJSONEditor {
                jsonEditor
            }

            footer
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 430)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TailOps Actions")
                    .font(.title3.weight(.semibold))
                Text("Choose a host, paste a dashboard address, then save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.addHostActions()
            } label: {
                Label("Host", systemImage: "plus")
            }
            Button {
                importExportText = model.exportJSON()
                showsJSONEditor = true
            } label: {
                Label("JSON", systemImage: "curlybraces")
            }
        }
    }

    private var appControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App")
                .font(.callout.weight(.semibold))

            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { preferencesModel.launchAtLogin },
                    set: { preferencesModel.setLaunchAtLogin($0) }
                )
            )

            Text("TailOps now runs widget-first. The host app stays hidden and keeps the shared widget snapshot, settings, and quick actions available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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

#if DEBUG
#Preview("Settings") {
    TailOpsSettingsView(
        model: TailOpsActionSettingsModel(
            store: PreviewSettingsStore(),
            configuration: .preview
        ),
        preferencesModel: TailOpsPreferencesModel(store: PreviewSettingsStore())
    )
}

private struct PreviewSettingsStore: SharedSnapshotStoring {
    func load() throws -> TailnetSnapshot? { .preview }
    func save(_ snapshot: TailnetSnapshot) throws {}
    func loadActionConfiguration() throws -> TailnetActionConfiguration? { .preview }
    func saveActionConfiguration(_ configuration: TailnetActionConfiguration) throws {}
    func loadAppPreferences() throws -> TailOpsAppPreferences? { TailOpsAppPreferences() }
    func saveAppPreferences(_ preferences: TailOpsAppPreferences) throws {}
    func loadSettingsOpenRequest() throws -> TailOpsSettingsOpenRequest? { nil }
    func saveSettingsOpenRequest(_ request: TailOpsSettingsOpenRequest) throws {}
    func clearSettingsOpenRequest() throws {}
}
#endif
