import Foundation
import SwiftUI
import TailOpsCore
import TailOpsShared

@MainActor
final class TailnetMonitor: ObservableObject {
    @Published private(set) var snapshot = TailnetSnapshot(hosts: [])
    @Published private(set) var actionConfiguration = TailnetActionConfiguration()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let statusProvider: TailscaleStatusProviding
    private let parser = TailnetSnapshotParser()
    private let snapshotStore: SharedSnapshotStoring
    private let actionCatalog = HostActionCatalog()

    init(
        statusProvider: TailscaleStatusProviding,
        snapshotStore: SharedSnapshotStoring,
        initialSnapshot: TailnetSnapshot? = nil
    ) {
        self.statusProvider = statusProvider
        self.snapshotStore = snapshotStore
        if let initialSnapshot {
            snapshot = initialSnapshot
        } else if let stored = try? snapshotStore.load() {
            snapshot = stored
        }
        if let storedConfiguration = try? snapshotStore.loadActionConfiguration() {
            actionConfiguration = storedConfiguration
        }
    }

    var summary: TailnetSummary {
        TailnetSummary(hosts: snapshot.hosts)
    }

    var menuBarSymbol: String {
        switch summary.trafficLight {
        case .healthy:
            return "network"
        case .warning:
            return "exclamationmark.triangle"
        case .offline:
            return "wifi.slash"
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let data = try await statusProvider.statusJSON()
            let nextSnapshot = try parser.parse(data)
            snapshot = nextSnapshot
            lastError = nil
            try snapshotStore.save(nextSnapshot)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func actions(for host: TailnetHost) -> [HostAction] {
        HostActionCatalog(configuration: actionConfiguration).actions(for: host)
    }
}
