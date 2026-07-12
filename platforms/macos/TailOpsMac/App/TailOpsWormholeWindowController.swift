import AppKit
import SwiftUI
import TailOpsCore
import TailOpsShared
import UniformTypeIdentifiers

@MainActor
final class TailOpsWormholeWindowController {
    static let shared = TailOpsWormholeWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<TailOpsWormholeView>?
    private var model: TailOpsWormholeModel?

    private init() {}

    func show(request: TailOpsWormholeOpenRequest? = nil) {
        let model = self.model ?? TailOpsWormholeModel()
        self.model = model
        model.apply(request: request)

        let view = TailOpsWormholeView(model: model)
        if let window, let hostingController {
            hostingController.rootView = view
            show(window)
            return
        }

        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "TailOps Wormhole"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.setContentSize(NSSize(width: 620, height: 520))
        window.minSize = NSSize(width: 540, height: 460)
        window.isReleasedWhenClosed = false
        window.center()

        self.hostingController = hostingController
        self.window = window
        show(window)
    }

    private func show(_ window: NSWindow) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

@MainActor
final class TailOpsWormholeModel: NSObject, ObservableObject {
    @Published private(set) var configuration: TailOpsWormholeConfiguration
    @Published private(set) var executable: TailOpsWormholeExecutable?
    @Published var mode: TailOpsWormholeOpenRequest.Mode
    @Published var selectedContactID: String?
    @Published var selectedFileURL: URL?
    @Published var displayName: String
    @Published var pairingID: String
    @Published var tailnetNodeID: String
    @Published var sharedSecret: String
    @Published var inboxPath: String
    @Published private(set) var availableTailnetPeers: [TailnetHost]
    @Published private(set) var pendingTransfers: [TailOpsWormholePendingTransfer]
    @Published private(set) var selectedPendingTransferID: String?
    @Published private(set) var status: Status
    @Published private(set) var lastOutput: String
    @Published private(set) var signalDeliveryError: String?
    @Published private(set) var signalServiceError: String?

    enum Status: Equatable {
        case ready
        case running(String)
        case succeeded(String)
        case failed(String)
    }

    private let store: SharedSnapshotStore
    private let secretStore: any TailOpsWormholeSecretStoring
    private let runner: TailOpsWormholeCommandRunner
    private let codeFactory: TailOpsWormholeCodeFactory

    init(
        store: SharedSnapshotStore = SharedSnapshotStore(),
        secretStore: any TailOpsWormholeSecretStoring = TailOpsWormholeSecretStore(),
        runner: TailOpsWormholeCommandRunner = TailOpsWormholeCommandRunner(),
        codeFactory: TailOpsWormholeCodeFactory = TailOpsWormholeCodeFactory()
    ) {
        self.store = store
        self.secretStore = secretStore
        self.runner = runner
        self.codeFactory = codeFactory

        let loadedConfiguration: TailOpsWormholeConfiguration
        let loadError: String?
        do {
            loadedConfiguration = try store.loadWormholeConfigurationMigratingSecrets(to: secretStore)
                ?? TailOpsWormholeConfiguration()
            loadError = nil
        } catch {
            loadedConfiguration = (try? store.loadWormholeConfiguration()) ?? TailOpsWormholeConfiguration()
            loadError = "Wormhole pairing migration failed: \(error.localizedDescription)"
        }
        configuration = loadedConfiguration
        executable = runner.discoverExecutable()
        mode = .receive
        selectedContactID = loadedConfiguration.contacts.first?.id
        selectedFileURL = nil
        displayName = loadedConfiguration.contacts.first?.displayName ?? "Paired Mac"
        pairingID = loadedConfiguration.contacts.first?.pairingID ?? ""
        tailnetNodeID = loadedConfiguration.contacts.first?.tailnetNodeID ?? ""
        let initialSecret: String
        let secretLoadError: String?
        if let firstContact = loadedConfiguration.contacts.first {
            do {
                if let secret = try secretStore.secret(for: firstContact.id) {
                    initialSecret = secret
                    secretLoadError = nil
                } else {
                    initialSecret = ""
                    secretLoadError = TailOpsWormholeSecretUnavailableError(
                        contactName: firstContact.displayName
                    ).localizedDescription
                }
            } catch {
                initialSecret = ""
                secretLoadError = error.localizedDescription
            }
        } else {
            initialSecret = ""
            secretLoadError = nil
        }
        sharedSecret = initialSecret
        inboxPath = loadedConfiguration.inboxPath
        availableTailnetPeers = ((try? store.load())?.hosts ?? [])
            .filter { $0.role == .peer }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        pendingTransfers = (try? store.loadWormholePendingTransfers()) ?? []
        selectedPendingTransferID = nil
        status = (loadError ?? secretLoadError).map(Status.failed) ?? .ready
        lastOutput = ""
        signalDeliveryError = nil
        signalServiceError = nil
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(signalServiceDidFail(_:)),
            name: .tailOpsWormholeSignalServiceFailed,
            object: nil
        )
    }

    @objc nonisolated private func signalServiceDidFail(_ notification: Notification) {
        let message = notification.object as? String
        Task { @MainActor [weak self, message] in
            self?.signalServiceError = message
        }
    }

    var selectedContact: TailOpsWormholeContact? {
        if let selectedContactID,
           let contact = configuration.contact(id: selectedContactID) {
            return contact
        }
        return configuration.contacts.first
    }

    var currentCode: TailOpsWormholeTransferCode? {
        guard let selectedContact,
              let secret = try? requiredSecret(for: selectedContact)
        else { return nil }
        return codeFactory.code(for: selectedContact, sharedSecret: secret)
    }

    var selectedPendingTransfer: TailOpsWormholePendingTransfer? {
        if let selectedPendingTransferID,
           let pendingTransfer = pendingTransfers.first(where: { $0.id == selectedPendingTransferID }) {
            return pendingTransfer
        }
        guard let selectedContact else { return nil }
        return pendingTransfers.first {
            $0.contactID == selectedContact.id || $0.pairingID == selectedContact.pairingID
        }
    }

    var receiveCode: String? {
        guard let selectedContact,
              let secret = try? requiredSecret(for: selectedContact)
        else { return nil }
        return codeFactory.code(
            for: selectedContact,
            sharedSecret: secret,
            date: selectedPendingTransfer?.createdAt ?? Date()
        ).code
    }

    var setupCommand: String {
        TailOpsWormholeCommandRunner.installCommand
    }

    var setupText: String {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPairingID = pairingID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecret = sharedSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        TailOps Wormhole setup
        Name: \(cleanName.isEmpty ? "Paired Mac" : cleanName)
        Pairing ID: \(cleanPairingID)
        Setup Secret: \(cleanSecret)
        Inbox: \(inboxPath)

        Put the same Pairing ID and Setup Secret into TailOps Wormhole on both Macs, then Save Pairing.
        """
    }

    var selectedFileName: String {
        selectedFileURL?.lastPathComponent ?? "Choose file"
    }

    var selectedContactName: String {
        selectedContact?.displayName ?? displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Paired Mac"
    }

    var resolvedInboxPath: String {
        NSString(string: inboxPath).expandingTildeInPath
    }

    func apply(request: TailOpsWormholeOpenRequest?) {
        reload()
        guard let request else { return }
        mode = request.mode
        selectedPendingTransferID = request.pendingTransferID
        if let contactID = request.contactID,
           configuration.contact(id: contactID) != nil {
            selectedContactID = contactID
        }
    }

    func reload() {
        do {
            configuration = try store.loadWormholeConfigurationMigratingSecrets(to: secretStore)
                ?? TailOpsWormholeConfiguration()
        } catch {
            configuration = (try? store.loadWormholeConfiguration()) ?? TailOpsWormholeConfiguration()
            status = .failed("Wormhole pairing migration failed: \(error.localizedDescription)")
        }
        pendingTransfers = (try? store.loadWormholePendingTransfers()) ?? []
        availableTailnetPeers = ((try? store.load())?.hosts ?? [])
            .filter { $0.role == .peer }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        executable = runner.discoverExecutable()
        if selectedContactID == nil || configuration.contact(id: selectedContactID ?? "") == nil {
            selectedContactID = configuration.contacts.first?.id
        }
        if let selectedContact {
            tailnetNodeID = selectedContact.tailnetNodeID ?? ""
            do {
                sharedSecret = try secretStore.secret(for: selectedContact.id) ?? ""
                if sharedSecret.isEmpty {
                    status = .failed(
                        TailOpsWormholeSecretUnavailableError(contactName: selectedContact.displayName)
                            .localizedDescription
                    )
                }
            } catch {
                sharedSecret = ""
                status = .failed(error.localizedDescription)
            }
        }
        inboxPath = configuration.inboxPath
    }

    func checkAgain() {
        executable = runner.discoverExecutable()
        status = executable == nil ? .failed("wormhole is still missing.") : .ready
    }

    func selectContact(id: String) {
        guard let contact = configuration.contact(id: id) else { return }
        selectedContactID = id
        displayName = contact.displayName
        pairingID = contact.pairingID
        tailnetNodeID = contact.tailnetNodeID ?? ""
        do {
            sharedSecret = try secretStore.secret(for: contact.id) ?? ""
        } catch {
            sharedSecret = ""
            status = .failed(error.localizedDescription)
        }
    }

    func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(setupCommand, forType: .string)
        status = .succeeded("Copied install command.")
    }

    func copySetupText() {
        guard !pairingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sharedSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            status = .failed("Generate or enter a setup secret first.")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(setupText, forType: .string)
        status = .succeeded("Copied pairing setup.")
    }

    func openHomebrewFormula() {
        if let url = URL(string: "https://formulae.brew.sh/formula/magic-wormhole") {
            NSWorkspace.shared.open(url)
        }
    }

    func generateSecret() {
        sharedSecret = UUID().uuidString + "-" + UUID().uuidString
    }

    func saveContact() {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPairingID = pairingID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecret = sharedSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNodeID = tailnetNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanPairingID.isEmpty, !cleanSecret.isEmpty, !cleanNodeID.isEmpty else {
            status = .failed("Name, pairing ID, setup secret, and Tailnet node ID are required.")
            return
        }

        let existing = configuration.contacts.filter { $0.displayName != cleanName }
        let contact = TailOpsWormholeContact(
            id: configuration.contacts.first { $0.displayName == cleanName }?.id ?? UUID().uuidString,
            displayName: cleanName,
            pairingID: cleanPairingID,
            tailnetNodeID: cleanNodeID
        )
        let updatedConfiguration = TailOpsWormholeConfiguration(
            contacts: existing + [contact],
            inboxPath: inboxPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? TailOpsWormholeConfiguration().inboxPath
                : inboxPath,
            pendingSignalPort: configuration.pendingSignalPort
        )

        do {
            try secretStore.save(secret: cleanSecret, for: contact.id)
            try store.saveWormholeConfiguration(updatedConfiguration)
            configuration = updatedConfiguration
            selectedContactID = contact.id
            status = .succeeded("Saved Wormhole pairing.")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK else { return }
        selectedFileURL = panel.url
    }

    func selectFile(_ fileURL: URL) {
        selectedFileURL = fileURL
        mode = .send
        status = .succeeded("Ready to send \(fileURL.lastPathComponent) to \(selectedContactName).")
    }

    func sendSelectedFile() {
        guard let selectedFileURL else {
            status = .failed("Choose a file first.")
            return
        }
        guard let selectedContact else {
            status = .failed("Save a Wormhole pairing first.")
            return
        }
        let createdAt = Date()
        let transferCode: TailOpsWormholeTransferCode
        do {
            let secret = try requiredSecret(for: selectedContact)
            transferCode = codeFactory.code(
                for: selectedContact,
                sharedSecret: secret,
                date: createdAt
            )
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        let pendingTransfer = createPendingTransfer(
            fileURL: selectedFileURL,
            createdAt: createdAt,
            expiresAt: transferCode.validUntil
        )

        Task {
            signalDeliveryError = nil
            if let pendingTransfer {
                do {
                    _ = try await TailOpsWormholePendingSignalClient(
                        store: store,
                        secretStore: secretStore
                    ).publish(pendingTransfer, to: selectedContact)
                } catch {
                    signalDeliveryError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            let didComplete = await runTransfer(
                title: "Sending \(selectedFileURL.lastPathComponent)",
                successMessage: "Sent \(selectedFileURL.lastPathComponent) to \(selectedContactName)."
            ) {
                try await self.runner.send(fileURL: selectedFileURL, code: transferCode.code)
            }
            if didComplete, let pendingTransfer {
                clearPendingTransfer(id: pendingTransfer.id)
            }
        }
    }

    func send(fileURL: URL) {
        selectedFileURL = fileURL
        sendSelectedFile()
    }

    func receiveIntoInbox() {
        guard let code = receiveCode else {
            status = .failed("Save a Wormhole pairing with an available Keychain secret first.")
            return
        }

        let inboxURL = URL(fileURLWithPath: resolvedInboxPath)
        Task {
            _ = await runTransfer(
                title: "Receiving into \(inboxURL.path)",
                successMessage: "Received file in \(inboxURL.path)."
            ) {
                try await self.runner.receive(code: code, inboxURL: inboxURL)
            }
        }
    }

    private func runTransfer(
        title: String,
        successMessage: String,
        operation: @MainActor @escaping () async throws -> TailOpsWormholeCommandResult
    ) async -> Bool {
        status = .running(title)
        lastOutput = ""

        do {
            let result = try await operation()
            lastOutput = result.output
            status = .succeeded(successMessage)
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastOutput = message
            status = .failed(message)
            return false
        }
    }

    private func createPendingTransfer(
        fileURL: URL,
        createdAt: Date,
        expiresAt: Date
    ) -> TailOpsWormholePendingTransfer? {
        guard let selectedContact else { return nil }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value
        let transfer = TailOpsWormholePendingTransfer(
            contactID: selectedContact.id,
            pairingID: selectedContact.pairingID,
            senderName: Host.current().localizedName ?? NSFullUserName(),
            fileName: fileURL.lastPathComponent,
            fileSizeBytes: fileSize,
            direction: .outgoing,
            createdAt: createdAt,
            expiresAt: expiresAt
        )

        do {
            var transfers = try store.loadWormholePendingTransfers()
            transfers.removeAll { $0.id == transfer.id }
            transfers.append(transfer)
            try store.saveWormholePendingTransfers(transfers)
            pendingTransfers = transfers
        } catch {
            status = .failed(error.localizedDescription)
        }

        return transfer
    }

    private func requiredSecret(for contact: TailOpsWormholeContact) throws -> String {
        guard let secret = try secretStore.secret(for: contact.id), !secret.isEmpty else {
            throw TailOpsWormholeSecretUnavailableError(contactName: contact.displayName)
        }
        return secret
    }

    private func clearPendingTransfer(id: String) {
        do {
            var transfers = try store.loadWormholePendingTransfers()
            transfers.removeAll { $0.id == id }
            try store.saveWormholePendingTransfers(transfers)
            pendingTransfers = transfers
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

private struct TailOpsWormholeSecretUnavailableError: LocalizedError {
    let contactName: String

    var errorDescription: String? {
        "The setup secret for \(contactName) is unavailable in Keychain. Enter it again and save the pairing."
    }
}

struct TailOpsWormholeView: View {
    @ObservedObject var model: TailOpsWormholeModel
    @State private var showsSetupSecret = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.executable == nil {
                missingExecutableView
            } else {
                pairingView
                pairedComputerView
            }

            statusView
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 430, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Wormhole")
                    .font(.title2.weight(.semibold))
                if let executable = model.executable {
                    Text(executable.displayPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Magic Wormhole setup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                model.checkAgain()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Check again")
        }
    }

    private var missingExecutableView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Install Magic Wormhole", systemImage: "shippingbox")
                .font(.headline)

            Text("TailOps looks for `wormhole` in Homebrew and PATH locations.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Text(model.setupCommand)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    model.copyInstallCommand()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button {
                    model.openHomebrewFormula()
                } label: {
                    Label("Formula", systemImage: "safari")
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var pairingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pairing", systemImage: "person.2.badge.key")
                    .font(.headline)
                Spacer()
                if !model.configuration.contacts.isEmpty {
                    Picker("Contact", selection: Binding(
                        get: { model.selectedContactID ?? "" },
                        set: { model.selectContact(id: $0) }
                    )) {
                        ForEach(model.configuration.contacts) { contact in
                            Text(contact.displayName).tag(contact.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Name")
                        .foregroundStyle(.secondary)
                    TextField("Paired Mac", text: $model.displayName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Pairing ID")
                        .foregroundStyle(.secondary)
                    TextField("shared-pairing", text: $model.pairingID)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Tailnet Node ID")
                        .foregroundStyle(.secondary)
                    if model.availableTailnetPeers.isEmpty {
                        TextField("Stable peer ID from tailscale status", text: $model.tailnetNodeID)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Tailnet peer", selection: $model.tailnetNodeID) {
                            Text("Choose a peer").tag("")
                            ForEach(model.availableTailnetPeers) { host in
                                Text(host.name).tag(host.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
                GridRow {
                    Text("Setup Secret")
                        .foregroundStyle(.secondary)
                    HStack {
                        Group {
                            if showsSetupSecret {
                                TextField("Shared once with paired Mac", text: $model.sharedSecret)
                            } else {
                                SecureField("Shared once with paired Mac", text: $model.sharedSecret)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        Button {
                            model.generateSecret()
                        } label: {
                            Image(systemName: "dice")
                        }
                        .help("Generate setup secret")
                        Button {
                            showsSetupSecret.toggle()
                        } label: {
                            Image(systemName: showsSetupSecret ? "eye.slash" : "eye")
                        }
                        .help(showsSetupSecret ? "Hide setup secret" : "Show setup secret")
                    }
                }
                GridRow {
                    Text("Inbox")
                        .foregroundStyle(.secondary)
                    TextField("~/Desktop/TailOps Inbox", text: $model.inboxPath)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button {
                    model.saveContact()
                } label: {
                    Label("Save Pairing", systemImage: "checkmark.circle")
                }
                Button {
                    model.copySetupText()
                } label: {
                    Label("Copy Setup", systemImage: "doc.on.doc")
                }
                Spacer()
                if let code = model.currentCode {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(code.code)
                            .font(.callout.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                        Text("Valid until \(code.validUntil.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var pairedComputerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(isDropTargeted ? 0.34 : 0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: "laptopcomputer")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selectedContactName)
                        .font(.headline)
                    Text("Drop a file here, or choose one below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let pendingTransfer = model.selectedPendingTransfer {
                        Text("Pending: \(pendingTransfer.fileName) from \(pendingTransfer.senderName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                    Text("Received files land in \(model.resolvedInboxPath)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                if let code = model.currentCode {
                    Text(code.code)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    model.chooseFile()
                } label: {
                    Label(model.selectedFileName, systemImage: "doc.badge.plus")
                }
                .lineLimit(1)

                Button {
                    model.sendSelectedFile()
                } label: {
                    Label("Send to \(model.selectedContactName)", systemImage: "paperplane")
                }
                .disabled(model.selectedFileURL == nil || model.currentCode == nil || isRunning)

                Spacer()

                Button {
                    model.receiveIntoInbox()
                } label: {
                    Label("Receive from \(model.selectedContactName)", systemImage: "tray.and.arrow.down")
                }
                .disabled(model.currentCode == nil || isRunning)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(isDropTargeted || isRunning ? 0.2 : 0.08),
                    Color.primary.opacity(0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(isDropTargeted || isRunning ? 0.85 : 0.28), lineWidth: isDropTargeted ? 2 : 1)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleFileDrop(providers)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.status {
            case .ready:
                EmptyView()
            case .running(let message):
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(message)
                        .font(.callout)
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            case .succeeded(let message):
                statusMessage(message, systemImage: "checkmark.circle.fill", color: .green)
            case .failed(let message):
                statusMessage(message, systemImage: "exclamationmark.triangle.fill", color: .orange)
            }
            if let signalDeliveryError = model.signalDeliveryError {
                statusMessage(
                    "File transfer continues, but the paired Mac was not notified: \(signalDeliveryError)",
                    systemImage: "bell.slash.fill",
                    color: .orange
                )
            }
            if let signalServiceError = model.signalServiceError {
                statusMessage(
                    signalServiceError,
                    systemImage: "network.slash",
                    color: .orange
                )
            }
        }
    }

    private var isRunning: Bool {
        if case .running = model.status {
            return true
        }
        return false
    }

    private func statusMessage(_ message: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(message)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(6)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let fileURL = wormholeFileURL(from: item) else { return }
            Task { @MainActor in
                model.send(fileURL: fileURL)
            }
        }

        return true
    }
}

private nonisolated func wormholeFileURL(from item: NSSecureCoding?) -> URL? {
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#if DEBUG
#Preview("Wormhole") {
    TailOpsWormholeView(model: TailOpsWormholeModel())
        .frame(width: 620, height: 520)
}
#endif
