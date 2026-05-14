import Foundation
import TailOpsCore
import TailOpsShared
import WidgetKit

@MainActor
final class TailOpsActionSettingsModel: ObservableObject {
    @Published var hostActions: [EditableHostActions]
    @Published private(set) var saveError: String?
    @Published private(set) var importExportMessage: String?

    private let store: SharedSnapshotStoring

    init(store: SharedSnapshotStoring = SharedSnapshotStore(), configuration: TailnetActionConfiguration? = nil) {
        self.store = store
        let initialConfiguration = configuration ?? (try? store.loadActionConfiguration()) ?? TailnetActionConfiguration()
        hostActions = initialConfiguration.hostActions.map(EditableHostActions.init)
    }

    var configuration: TailnetActionConfiguration {
        TailnetActionConfiguration(
            hostActions: hostActions
                .filter { !$0.hostID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { host in
                    TailnetHostActionConfiguration(
                        hostID: host.hostID.trimmingCharacters(in: .whitespacesAndNewlines),
                        actions: host.actions.compactMap(\.quickAction)
                    )
                }
        )
    }

    var validationIssues: [TailnetActionValidationIssue] {
        configuration.validationIssues()
    }

    var canSave: Bool {
        validationIssues.isEmpty
    }

    func addHostActions() {
        hostActions.append(EditableHostActions(hostID: "", actions: [EditableQuickAction()]))
    }

    func removeHostActions(id: EditableHostActions.ID) {
        hostActions.removeAll { $0.id == id }
    }

    func addAction(to hostID: EditableHostActions.ID) {
        guard let index = hostActions.firstIndex(where: { $0.id == hostID }) else { return }
        hostActions[index].actions.append(EditableQuickAction())
    }

    func removeAction(_ actionID: EditableQuickAction.ID, from hostID: EditableHostActions.ID) {
        guard let index = hostActions.firstIndex(where: { $0.id == hostID }) else { return }
        hostActions[index].actions.removeAll { $0.id == actionID }
    }

    func save() {
        guard canSave else {
            saveError = "Fix validation issues before saving."
            return
        }
        do {
            try store.saveActionConfiguration(configuration)
            WidgetCenter.shared.reloadTimelines(ofKind: "dev.tailops.monitor.widget")
            saveError = nil
            importExportMessage = "Saved actions."
        } catch {
            saveError = error.localizedDescription
        }
    }

    func exportJSON() -> String {
        do {
            let data = try JSONEncoder.tailopsSettings.encode(configuration)
            importExportMessage = "Exported JSON."
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            saveError = error.localizedDescription
            return "{}"
        }
    }

    func importJSON(_ text: String) {
        do {
            let data = Data(text.utf8)
            let configuration = try JSONDecoder.tailopsSettings.decode(TailnetActionConfiguration.self, from: data)
            let issues = configuration.validationIssues()
            guard issues.isEmpty else {
                saveError = issues.map(\.message).joined(separator: " ")
                return
            }
            hostActions = configuration.hostActions.map(EditableHostActions.init)
            saveError = nil
            importExportMessage = "Imported actions."
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private extension JSONEncoder {
    static var tailopsSettings: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var tailopsSettings: JSONDecoder {
        JSONDecoder()
    }
}

struct EditableHostActions: Identifiable, Equatable {
    let id: UUID
    var hostID: String
    var actions: [EditableQuickAction]

    init(id: UUID = UUID(), hostID: String, actions: [EditableQuickAction]) {
        self.id = id
        self.hostID = hostID
        self.actions = actions
    }

    init(configuration: TailnetHostActionConfiguration) {
        id = UUID()
        hostID = configuration.hostID
        actions = configuration.actions.map(EditableQuickAction.init)
    }
}

struct EditableQuickAction: Identifiable, Equatable {
    let id: UUID
    var emoji: String
    var title: String
    var kind: TailnetQuickAction.Kind
    var target: String

    init(
        id: UUID = UUID(),
        emoji: String = "🧭",
        title: String = "Dashboard",
        kind: TailnetQuickAction.Kind = .url,
        target: String = ""
    ) {
        self.id = id
        self.emoji = emoji
        self.title = title
        self.kind = kind
        self.target = target
    }

    init(action: TailnetQuickAction) {
        id = UUID()
        emoji = action.emoji
        title = action.title
        kind = action.kind
        target = action.target
    }

    var quickAction: TailnetQuickAction? {
        let cleanEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmoji.isEmpty, !cleanTitle.isEmpty, !cleanTarget.isEmpty else { return nil }
        return TailnetQuickAction(emoji: cleanEmoji, title: cleanTitle, kind: kind, target: cleanTarget)
    }
}
