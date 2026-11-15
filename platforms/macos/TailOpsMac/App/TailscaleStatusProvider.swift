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
    /// This Mac's own observer reading, or nil when the observer is not installed here.
    func localActivity() async throws -> TailnetAgentActivity?
    /// Another host's counts-only summary from the read-only file it shares on the tailnet.
    func activity(from source: String, at url: URL) async throws -> TailnetAgentActivity
}

/// Reads the Fleet agent observer's counts: this Mac's from disk, another host's with one
/// HTTPS GET of the summary it shares with Tailscale Serve. Nothing logs in to the host and
/// nothing can run there; the request carries no cookies or credentials.
struct FleetAgentActivityProvider: FleetAgentActivityProviding {
    static let maximumBytes = 64 * 1_024
    private let parser = TailnetAgentActivityParser()
    private let observerHome: URL
    private let session: URLSession

    init(observerHome: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Fleet Observer")) {
        self.observerHome = observerHome
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func localActivity() async throws -> TailnetAgentActivity? {
        // Observers installed before the summary existed only write state.json.
        for name in ["agent-summary.json", "state.json"] {
            let url = observerHome.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                return try parser.parse(Data(contentsOf: url), source: nil, readAt: Date())
            }
        }
        return nil
    }

    func activity(from source: String, at url: URL) async throws -> TailnetAgentActivity {
        guard url.scheme == "https" else {
            throw TailscaleStatusError.commandFailed("\(source) has no HTTPS address for its agent summary.")
        }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TailscaleStatusError.commandFailed("\(source) does not share an agent summary.")
        }
        guard data.count <= Self.maximumBytes else {
            throw TailscaleStatusError.commandFailed("\(source) returned an oversized agent summary.")
        }
        return try parser.parse(data, source: source, readAt: Date())
    }
}

/// Which tailnet hosts TailOps asks for agent counts. Only the host app reads this.
enum FleetAgentSettings {
    static let hostsKey = "FleetAgentHosts"

    static func hosts(in defaults: UserDefaults = .standard) -> [String] {
        (defaults.string(forKey: hostsKey) ?? "")
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter(SSHFleetHealthProvider.isValidSource)
    }
}
