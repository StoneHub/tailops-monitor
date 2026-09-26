import AppKit
import Foundation
import TailOpsCore

/// Checks GitHub Releases on demand and replaces /Applications/TailOps.app with a
/// download that passes the same code-signature checks as the running app.
/// Gatekeeper is left in charge: a quarantined download is refused, never cleared.
@MainActor
final class TailOpsAppUpdater: ObservableObject {
    static let shared = TailOpsAppUpdater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(ReleaseInfo)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var state = State.idle

    static let installPath = "/Applications/TailOps.app"
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/TailOpsMac/update.log")

    private let processRunner = BoundedProcessRunner()
    private var progressObservation: NSKeyValueObservation?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    func check() {
        guard !isBusy else { return }
        state = .checking
        Task {
            do {
                var request = URLRequest(url: TailOpsRelease.listURL)
                request.timeoutInterval = 15
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                guard http.statusCode == 200 else { throw UpdateError("GitHub answered \(http.statusCode).") }

                let release: ReleaseInfo
                do {
                    release = try ReleaseInfo.newest(from: data)
                } catch ReleaseInfo.ParseError.noRelease {
                    state = .upToDate(Self.currentVersion)
                    return
                }
                guard let installed = SemanticVersion.parse(Self.currentVersion) else {
                    throw UpdateError("Installed version \(Self.currentVersion) is not a version.")
                }
                guard release.version > installed else {
                    state = .upToDate(Self.currentVersion)
                    return
                }
                let runningTeam = try await teamIdentifier(of: Bundle.main.bundleURL)
                guard runningTeam == TailOpsRelease.officialTeamIdentifier else {
                    throw UpdateError(
                        "This copy is signed by team \(runningTeam). Install a TailOps release once to use in-app updates."
                    )
                }
                state = .available(release)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func install() {
        guard case .available(let release) = state else { return }
        state = .downloading(0)
        Task {
            let staging = FileManager.default.temporaryDirectory.appending(path: "tailops-update-\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                log("update \(Self.currentVersion) -> \(release.version); staging \(staging.path)")
                let zip = try await download(release, to: staging)
                log("downloaded \(zip.lastPathComponent), \(release.assetSize) bytes")
                state = .installing
                try await run("/usr/bin/ditto", "-x", "-k", zip.path, staging.path)
                let bundle = staging.appending(path: "TailOps.app")
                try await verify(bundle, expecting: release.version)
                log("verified \(bundle.path)")
                try swap(bundle, staging: staging)
            } catch {
                log("failed: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: staging)
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func download(_ release: ReleaseInfo, to directory: URL) async throws -> URL {
        let destination = directory.appending(path: release.downloadURL.lastPathComponent)
        let response: URLResponse = try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: release.downloadURL) { url, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                // Move inside the handler; the system deletes the temporary file once it returns.
                do {
                    try FileManager.default.moveItem(at: url, to: destination)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(fraction)
                }
            }
            task.resume()
        }
        progressObservation = nil

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError("Download failed with status \(status).") }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? -1
        guard size == release.assetSize else {
            throw UpdateError("Download is \(size) bytes; the release lists \(release.assetSize).")
        }
        return destination
    }

    private func verify(_ bundle: URL, expecting version: SemanticVersion) async throws {
        guard FileManager.default.fileExists(atPath: bundle.path) else {
            throw UpdateError("The download did not contain TailOps.app.")
        }
        try await run("/usr/bin/codesign", "--verify", "--deep", "--strict", bundle.path)
        let running = try await teamIdentifier(of: Bundle.main.bundleURL)
        let downloaded = try await teamIdentifier(of: bundle)
        guard running == downloaded else {
            throw UpdateError("Signing team \(downloaded) does not match the installed app (\(running)).")
        }
        if Self.isQuarantined(bundle) {
            throw UpdateError(
                "macOS quarantined the download, so TailOps will not install it. Download the release from GitHub and open it from Finder instead."
            )
        }
        let info = bundle.appending(path: "Contents/Info.plist")
        let bundleVersion = (NSDictionary(contentsOf: info)?["CFBundleShortVersionString"] as? String)
            .flatMap(SemanticVersion.parse)
        guard bundleVersion == version else {
            throw UpdateError(
                "Downloaded app reports version \(bundleVersion?.description ?? "unknown"), expected \(version)."
            )
        }
    }

    private static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    /// The running app cannot replace itself, so a detached shell script swaps the
    /// bundles after this process exits, restores the old app if the new one fails
    /// its signature check, and relaunches.
    private func swap(_ bundle: URL, staging: URL) throws {
        let script = staging.appending(path: "swap.sh")
        let text = """
        #!/bin/sh
        pid="$1"; new="$2"; previous="$3"; log="$4"; target="\(Self.installPath)"
        note() { echo "$(date '+%Y-%m-%dT%H:%M:%S') swap: $1" >> "$log"; }
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        note "app pid $pid exited"
        if [ -e "$target" ]; then
            mv "$target" "$previous" || { note "could not move the current app aside"; exit 1; }
            note "moved current app to $previous"
        fi
        if mv "$new" "$target"; then
            if codesign --verify --deep --strict "$target" 2>>"$log"; then
                note "installed new app at $target"
            else
                note "new app failed the signature check; restoring the previous app"
                mv "$target" "$previous.rejected" && [ -e "$previous" ] && mv "$previous" "$target"
            fi
        else
            note "could not move the new app into place; restoring the previous app"
            [ -e "$previous" ] && mv "$previous" "$target"
        fi
        open "$target" && note "launched $target"
        [ -e "$previous" ] && rm -rf "$previous" && note "removed the previous app"
        """
        try text.write(to: script, atomically: true, encoding: .utf8)

        let previous = staging.appending(path: "TailOps-previous.app")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            bundle.path,
            previous.path,
            Self.logURL.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        log("swap script started (pid \(process.processIdentifier)); quitting so it can replace \(Self.installPath)")
        NSApp.terminate(nil)
    }

    private func teamIdentifier(of bundle: URL) async throws -> String {
        let result = try await processRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["-dv", bundle.path],
            timeout: 30,
            maximumStandardOutputBytes: 4_096,
            maximumStandardErrorBytes: 64 * 1_024
        )
        guard result.terminationStatus == 0 else {
            throw UpdateError("codesign could not read \(bundle.lastPathComponent).")
        }
        let text = String(decoding: result.stderr, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("TeamIdentifier=") {
            return String(line.dropFirst("TeamIdentifier=".count))
        }
        throw UpdateError("\(bundle.lastPathComponent) has no TeamIdentifier.")
    }

    private func run(_ executable: String, _ arguments: String...) async throws {
        let result = try await processRunner.run(
            executableURL: URL(fileURLWithPath: executable),
            arguments: arguments,
            timeout: 120,
            maximumStandardOutputBytes: 64 * 1_024,
            maximumStandardErrorBytes: 64 * 1_024
        )
        let name = URL(fileURLWithPath: executable).lastPathComponent
        log("\(name) \(arguments.joined(separator: " ")) -> exit \(result.terminationStatus)")
        guard result.terminationStatus == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError("\(name) failed: \(stderr.isEmpty ? "exit \(result.terminationStatus)" : stderr)")
        }
    }

    // Local time in the format the swap script writes with date(1), so both halves read in order.
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private func log(_ message: String) {
        let line = "\(Self.stamp.string(from: Date())) \(message)\n"
        let url = Self.logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct UpdateError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
