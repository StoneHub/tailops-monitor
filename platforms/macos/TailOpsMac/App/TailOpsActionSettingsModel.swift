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
        let hosts = (try? store.load()?.hosts) ?? []
        hostActions = Self.mergedHostActions(hosts: hosts, configuration: initialConfiguration)
    }

    var configuration: TailnetActionConfiguration {
        TailnetActionConfiguration(
            hostActions: hostActions
                .filter {
                    !$0.hostID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !$0.actions.compactMap(\.quickAction).isEmpty
                }
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

    func addDashboard(to hostID: EditableHostActions.ID, target: String) {
        let normalizedTarget = Self.normalizedDashboardTarget(target)
        guard !normalizedTarget.isEmpty,
              let index = hostActions.firstIndex(where: { $0.id == hostID })
        else {
            return
        }

        hostActions[index].actions.append(
            EditableQuickAction(
                emoji: "🧭",
                title: Self.dashboardTitle(for: normalizedTarget),
                kind: .url,
                target: normalizedTarget
            )
        )
    }

    func removeAction(_ actionID: EditableQuickAction.ID, from hostID: EditableHostActions.ID) {
        guard let index = hostActions.firstIndex(where: { $0.id == hostID }) else { return }
        hostActions[index].actions.removeAll { $0.id == actionID }
    }

    @discardableResult
    func save() -> Bool {
        guard canSave else {
            saveError = "Fix validation issues before saving."
            return false
        }
        do {
            try store.saveActionConfiguration(configuration)
            WidgetCenter.shared.reloadTimelines(ofKind: "dev.tailops.monitor.widget")
            saveError = nil
            importExportMessage = "Saved actions."
            return true
        } catch {
            saveError = error.localizedDescription
            return false
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

    private static func mergedHostActions(hosts: [TailnetHost], configuration: TailnetActionConfiguration) -> [EditableHostActions] {
        var remainingConfigurations = configuration.hostActions
        var rows: [EditableHostActions] = hosts.map { host in
            let matchIndex = remainingConfigurations.firstIndex { hostConfiguration in
                identifiers(for: host).contains(hostConfiguration.hostID)
            }
            let matchedConfiguration = matchIndex.map { remainingConfigurations.remove(at: $0) }

            return EditableHostActions(
                hostID: preferredIdentifier(for: host),
                actions: matchedConfiguration?.actions.map(EditableQuickAction.init) ?? [],
                displayName: host.name,
                displayDetail: host.magicDNSName ?? host.primaryAddress,
                status: host.status,
                isKnownHost: true
            )
        }

        rows.append(contentsOf: remainingConfigurations.map(EditableHostActions.init))
        return rows
    }

    private static func preferredIdentifier(for host: TailnetHost) -> String {
        host.magicDNSName ?? host.primaryAddress ?? host.name
    }

    private static func identifiers(for host: TailnetHost) -> Set<String> {
        Set([host.id, host.name, host.magicDNSName, host.primaryAddress].compactMap(\.self))
    }

    private static func normalizedDashboardTarget(_ target: String) -> String {
        let cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTarget.isEmpty else { return "" }
        if URL(string: cleanTarget)?.scheme != nil {
            return cleanTarget
        }
        return "http://\(cleanTarget)"
    }

    private static func dashboardTitle(for target: String) -> String {
        guard let url = URL(string: target),
              let host = url.host(percentEncoded: false),
              !host.isEmpty
        else {
            return "Dashboard"
        }

        if let port = url.port {
            return "\(port)"
        }

        return host
            .split(separator: ".")
            .first
            .map(String.init) ?? "Dashboard"
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
    var displayName: String?
    var displayDetail: String?
    var status: TailnetHost.Status?
    var isKnownHost: Bool

    init(
        id: UUID = UUID(),
        hostID: String,
        actions: [EditableQuickAction],
        displayName: String? = nil,
        displayDetail: String? = nil,
        status: TailnetHost.Status? = nil,
        isKnownHost: Bool = false
    ) {
        self.id = id
        self.hostID = hostID
        self.actions = actions
        self.displayName = displayName
        self.displayDetail = displayDetail
        self.status = status
        self.isKnownHost = isKnownHost
    }

    init(configuration: TailnetHostActionConfiguration) {
        id = UUID()
        hostID = configuration.hostID
        actions = configuration.actions.map(EditableQuickAction.init)
        displayName = nil
        displayDetail = nil
        status = nil
        isKnownHost = false
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
