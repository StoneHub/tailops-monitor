import SwiftUI
import TailOpsCore
import TailOpsShared

struct TailOpsSettingsView: View {
    @StateObject private var model: TailOpsActionSettingsModel
    @State private var importExportText = ""
    @State private var showsJSONEditor = false

    init(model: TailOpsActionSettingsModel = TailOpsActionSettingsModel()) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach($model.hostActions) { $hostActions in
                        HostActionsEditor(
                            hostActions: $hostActions,
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
        .frame(minWidth: 680, minHeight: 520)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TailOps Actions")
                    .font(.title3.weight(.semibold))
                Text("Match a host by name, MagicDNS, Tailscale IP, or host ID, then add widget buttons.")
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
            if let saveError = model.saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let importExportMessage = model.importExportMessage {
                Text(importExportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Kinds: URL opens dashboards, SSH opens ssh:// links, Copy is wired visually until App Intents are added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Save") {
                model.save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSave)
        }
    }
}

private struct HostActionsEditor: View {
    @Binding var hostActions: EditableHostActions
    let addAction: () -> Void
    let removeAction: (EditableQuickAction.ID) -> Void
    let removeHost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Host name, MagicDNS, IP, or ID", text: $hostActions.hostID)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                Button {
                    addAction()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .help("Add action")
                Button(role: .destructive) {
                    removeHost()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove host")
            }

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
                    .frame(minWidth: 260)

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
        )
    )
}

private struct PreviewSettingsStore: SharedSnapshotStoring {
    func load() throws -> TailnetSnapshot? { .preview }
    func save(_ snapshot: TailnetSnapshot) throws {}
    func loadActionConfiguration() throws -> TailnetActionConfiguration? { .preview }
    func saveActionConfiguration(_ configuration: TailnetActionConfiguration) throws {}
}
#endif
