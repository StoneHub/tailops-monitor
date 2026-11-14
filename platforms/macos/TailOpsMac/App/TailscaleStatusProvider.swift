import Foundation
import TailOpsCore

protocol TailscaleStatusProviding: Sendable {
    func statusJSON() async throws -> Data
}

protocol TailscalePingProviding: Sendable {
    func pingSummary(for host: TailnetHost) async throws -> TailnetPingSummary?
}

protocol TaildropFileTransferProviding: Sendable {
    func send(fileURL: URL, to host: TailnetHost) async throws
}

protocol TaildropTargetProviding: Sendable {
    func targets() async throws -> [TaildropTarget]
}

struct ProcessTailscaleStatusProvider: TailscaleStatusProviding {
    private let runner = TailscaleCommandRunner()

    func statusJSON() async throws -> Data {
        try await runner.run(arguments: ["status", "--json"]).stdout
    }
}

struct ProcessTailscalePingProvider: TailscalePingProviding {
    private let runner = TailscaleCommandRunner()
    private let parser = TailnetPingOutputParser()

    func pingSummary(for host: TailnetHost) async throws -> TailnetPingSummary? {
        guard let target = host.primaryAddress ?? host.magicDNSName else {
            return nil
        }

        let result = try await runner.run(arguments: [
            "ping",
            "--c", "6",
            "--timeout", "1500ms",
            "--until-direct=false",
            target
        ])
        let output = String(data: result.stdout, encoding: .utf8) ?? ""
        return parser.parse(output)
    }
}

struct ProcessTaildropFileTransferProvider: TaildropFileTransferProviding {
    private let runner = TailscaleCommandRunner()

    func send(fileURL: URL, to host: TailnetHost) async throws {
        guard let target = host.primaryAddress ?? host.magicDNSName else {
            throw TailscaleStatusError.commandFailed("No Tailscale address for \(host.name).")
        }

        _ = try await runner.run(arguments: [
            "file",
            "cp",
            fileURL.path,
            "\(target):"
        ], timeout: 10 * 60)
    }

    func send(fileURLs: [URL], to target: TaildropTarget) async throws {
        guard !fileURLs.isEmpty else { return }

        _ = try await runner.run(arguments: [
            "file",
            "cp"
        ] + fileURLs.map(\.path) + ["\(target.address):"], timeout: 10 * 60)
    }
}

struct ProcessTaildropTargetProvider: TaildropTargetProviding {
    private let runner = TailscaleCommandRunner()
    private let parser = TaildropTargetsParser()

    func targets() async throws -> [TaildropTarget] {
        let result = try await runner.run(arguments: ["file", "cp", "--targets"])
        let output = String(data: result.stdout, encoding: .utf8) ?? ""
        return parser.parse(output)
    }
}

struct TailscaleCommandRunner: Sendable {
    private let processRunner = BoundedProcessRunner()
    private let candidateExecutablePaths = [
        "/usr/local/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/bin/tailscale",
    ]

    func run(
        arguments: [String],
        timeout: TimeInterval = 20
    ) async throws -> (stdout: Data, stderr: Data) {
        guard let executableURL = candidateExecutablePaths
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else {
            throw TailscaleStatusError.executableNotFound(candidateExecutablePaths)
        }

        let result: BoundedProcessResult
        do {
            result = try await processRunner.run(
                executableURL: executableURL,
                arguments: arguments,
                timeout: timeout,
                maximumStandardOutputBytes: 8 * 1_024 * 1_024,
                maximumStandardErrorBytes: 256 * 1_024
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TailscaleStatusError.commandFailed(error.localizedDescription)
        }

        let command = "tailscale \(arguments.first ?? "")"
        guard result.terminationStatus == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TailscaleStatusError.commandFailed(
                message.isEmpty ? "\(command) exited with status \(result.terminationStatus)." : message
            )
        }
        guard !result.stdoutWasTruncated else {
            throw TailscaleStatusError.commandFailed("\(command) produced more output than TailOps accepts.")
        }

        return (result.stdout, result.stderr)
    }
}

enum TailscaleStatusError: LocalizedError {
    case executableNotFound([String])
    case commandFailed(String?)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let paths):
            return "Tailscale CLI not found. Checked: \(paths.joined(separator: ", "))"
        case .commandFailed(let message):
            return message?.isEmpty == false ? message : "The Tailscale CLI failed."
        }
    }
}

protocol FleetHealthProviding: Sendable {
    func health(from source: String) async throws -> TailnetNodeHealth
}

/// Reads a Linux node's health-only tailopsd document over the controller's existing
/// SSH login. The remote command is fixed and the host alias is validated, so the
/// configured value can only name a host.
struct SSHFleetHealthProvider: FleetHealthProviding {
    static let remotePath = "/var/lib/tailopsd/host-health.json"
    private let processRunner = BoundedProcessRunner()
    private let parser = TailnetNodeHealthParser()

    static func isValidSource(_ source: String) -> Bool {
        guard let first = source.first, first != "-", source.count <= 253 else { return false }
        return source.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-@".unicodeScalars.contains(scalar))
        }
    }

    func health(from source: String) async throws -> TailnetNodeHealth {
        guard Self.isValidSource(source) else {
            throw TailscaleStatusError.commandFailed("\(source) is not a valid SSH host.")
        }
        let result = try await processRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=8",
                "-o", "StrictHostKeyChecking=yes",
                "--", source,
                "cat", Self.remotePath,
            ],
            timeout: 20,
            maximumStandardOutputBytes: 256 * 1_024,
            maximumStandardErrorBytes: 16 * 1_024
        )
        guard result.terminationStatus == 0, !result.stdoutWasTruncated else {
            let message = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw TailscaleStatusError.commandFailed(message.isEmpty ? "ssh \(source) failed." : message)
        }
        return try parser.parse(result.stdout)
    }
}

/// Which Linux nodes TailOps asks for health. Only the host app reads this, so it lives
/// in the app's own defaults rather than the shared App Group.
enum FleetHealthSettings {
    static let sourcesKey = "FleetHealthSSHHosts"

    static func sources(in defaults: UserDefaults = .standard) -> [String] {
        (defaults.string(forKey: sourcesKey) ?? "")
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter(SSHFleetHealthProvider.isValidSource)
    }
}

protocol FleetAgentActivityProviding: Sendable {
    /// This Mac's own observer state, or nil when the observer is not installed here.
    func localActivity() async throws -> TailnetAgentActivity?
    func activity(from source: String) async throws -> TailnetAgentActivity
}

/// Reads the Fleet agent observer's `state.json`: from this Mac's disk, or from another
/// host over the controller's existing SSH login with a fixed command that only `cat`s
/// the observer's state from its Linux or macOS home.
struct FleetAgentActivityProvider: FleetAgentActivityProviding {
    static let remoteCommand =
        #"cat .local/state/fleet-observer/state.json 2>/dev/null || cat "Library/Application Support/Fleet Observer/state.json""#
    private let processRunner = BoundedProcessRunner()
    private let parser = TailnetAgentActivityParser()
    private let localStateURL: URL

    init(localStateURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Fleet Observer/state.json")) {
        self.localStateURL = localStateURL
    }

    func localActivity() async throws -> TailnetAgentActivity? {
        guard FileManager.default.fileExists(atPath: localStateURL.path) else { return nil }
        let data = try Data(contentsOf: localStateURL)
        return try parser.parse(data, source: nil, readAt: Date())
    }

    func activity(from source: String) async throws -> TailnetAgentActivity {
        guard SSHFleetHealthProvider.isValidSource(source) else {
            throw TailscaleStatusError.commandFailed("\(source) is not a valid SSH host.")
        }
        let result = try await processRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=8",
                "-o", "StrictHostKeyChecking=yes",
                "--", source,
                Self.remoteCommand,
            ],
            timeout: 20,
            maximumStandardOutputBytes: 512 * 1_024,
            maximumStandardErrorBytes: 16 * 1_024
        )
        guard result.terminationStatus == 0, !result.stdoutWasTruncated else {
            let message = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw TailscaleStatusError.commandFailed(message.isEmpty ? "ssh \(source) failed." : message)
        }
        return try parser.parse(result.stdout, source: source, readAt: Date())
    }
}
