import AppKit
import Foundation
import TailOpsCore

@MainActor
final class TaildropServiceProvider: NSObject {
    static let shared = TaildropServiceProvider()

    private let targetProvider: TaildropTargetProviding
    private let transferProvider = ProcessTaildropFileTransferProvider()

    init(targetProvider: TaildropTargetProviding = ProcessTaildropTargetProvider()) {
        self.targetProvider = targetProvider
    }

    @objc
    func sendWithTailOps(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let fileURLs = Self.fileURLs(from: pasteboard)
        guard !fileURLs.isEmpty else {
            error.pointee = "TailOps did not receive any files."
            return
        }

        Task { @MainActor in
            await presentTaildropPrompt(fileURLs: fileURLs)
        }
    }

    @MainActor
    private func presentTaildropPrompt(fileURLs: [URL]) async {
        NSApp.activate(ignoringOtherApps: true)

        do {
            let targets = try await targetProvider.targets().filter(\.isAvailable)
            guard !targets.isEmpty else {
                showMessage("No Taildrop targets are currently available.")
                return
            }

            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 28), pullsDown: false)
            for target in targets {
                popup.addItem(withTitle: "\(target.name) (\(target.address))")
            }

            let alert = NSAlert()
            alert.messageText = "Send with TailOps"
            alert.informativeText = fileURLs.count == 1
                ? "Send \(fileURLs[0].lastPathComponent) with Taildrop."
                : "Send \(fileURLs.count) files with Taildrop."
            alert.accessoryView = popup
            alert.addButton(withTitle: "Send")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let target = targets[popup.indexOfSelectedItem]
            try await transferProvider.send(fileURLs: fileURLs, to: target)
            showMessage("Sent \(fileURLs.count == 1 ? fileURLs[0].lastPathComponent : "\(fileURLs.count) files") to \(target.name).")
        } catch {
            showMessage(error.localizedDescription)
        }
    }

    @MainActor
    private func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "TailOps"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            return urls
        }

        return pasteboard.propertyList(forType: .fileURL) as? [URL] ?? []
    }
}
