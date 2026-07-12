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

        guard result.terminationStatus == 0 else {
            let message = String(data: result.stderr, encoding: .utf8)
            throw TailscaleStatusError.commandFailed(
                message?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
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
            return message?.isEmpty == false ? message : "tailscale status --json failed"
        }
    }
}
