import Foundation

struct TailOpsWormholeExecutable: Equatable, Sendable {
    let url: URL

    var displayPath: String {
        url.path
    }
}

struct TailOpsWormholeCommandResult: Equatable, Sendable {
    let executablePath: String
    let arguments: [String]
    let exitCode: Int32
    let output: String

    var succeeded: Bool {
        exitCode == 0
    }
}

enum TailOpsWormholeCommandError: LocalizedError, Equatable {
    case missingExecutable
    case launchFailed(String)
    case failed(exitCode: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "Magic Wormhole is not installed."
        case .launchFailed(let message):
            return message
        case .failed(let exitCode, let output):
            let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanOutput.isEmpty {
                return "wormhole exited with status \(exitCode)."
            }
            return cleanOutput
        }
    }
}

@MainActor
struct TailOpsWormholeCommandRunner {
    static let installCommand = "brew install magic-wormhole"

    private let fileManager: FileManager
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func discoverExecutable() -> TailOpsWormholeExecutable? {
        executableCandidates()
            .first { fileManager.isExecutableFile(atPath: $0.path) }
            .map(TailOpsWormholeExecutable.init(url:))
    }

    func send(fileURL: URL, code: String) async throws -> TailOpsWormholeCommandResult {
        guard let executable = discoverExecutable() else {
            throw TailOpsWormholeCommandError.missingExecutable
        }

        return try await run(
            executable: executable,
            arguments: ["send", "--code", code, fileURL.path],
            workingDirectory: fileURL.deletingLastPathComponent()
        )
    }

    func receive(code: String, inboxURL: URL) async throws -> TailOpsWormholeCommandResult {
        guard let executable = discoverExecutable() else {
            throw TailOpsWormholeCommandError.missingExecutable
        }

        try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        return try await run(
            executable: executable,
            arguments: ["receive", "--accept-file", code],
            workingDirectory: inboxURL
        )
    }

    private func executableCandidates() -> [URL] {
        var paths = [
            "/opt/homebrew/bin/wormhole",
            "/usr/local/bin/wormhole",
            "/usr/bin/wormhole"
        ]

        for pathComponent in environment["PATH", default: ""].split(separator: ":") {
            let candidate = String(pathComponent).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            paths.append(URL(fileURLWithPath: candidate).appendingPathComponent("wormhole").path)
        }

        var seen = Set<String>()
        return paths.compactMap { path in
            guard seen.insert(path).inserted else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    private func run(
        executable: TailOpsWormholeExecutable,
        arguments: [String],
        workingDirectory: URL
    ) async throws -> TailOpsWormholeCommandResult {
        let environment = commandEnvironment()
        return try await Task.detached(priority: .userInitiated) {
            try runBlocking(
                executableURL: executable.url,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
        }.value
    }

    private func commandEnvironment() -> [String: String] {
        var commandEnvironment = environment
        commandEnvironment["WORMHOLE_ACCEPT_FILE"] = "1"
        commandEnvironment["WORMHOLE_QR"] = "0"

        let requiredPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let currentPaths = commandEnvironment["PATH", default: ""]
            .split(separator: ":")
            .map(String.init)
        let mergedPaths = requiredPaths + currentPaths.filter { !requiredPaths.contains($0) }
        commandEnvironment["PATH"] = mergedPaths.joined(separator: ":")
        return commandEnvironment
    }
}

private func runBlocking(
    executableURL: URL,
    arguments: [String],
    workingDirectory: URL,
    environment: [String: String]
) throws -> TailOpsWormholeCommandResult {
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("tailops-wormhole-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)

    let outputHandle = try FileHandle(forWritingTo: outputURL)
    defer {
        try? outputHandle.close()
        try? FileManager.default.removeItem(at: outputURL)
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    process.environment = environment
    process.standardOutput = outputHandle
    process.standardError = outputHandle

    do {
        try process.run()
    } catch {
        throw TailOpsWormholeCommandError.launchFailed(error.localizedDescription)
    }

    process.waitUntilExit()
    try? outputHandle.synchronize()
    let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
    let output = String(decoding: outputData, as: UTF8.self)
    let result = TailOpsWormholeCommandResult(
        executablePath: executableURL.path,
        arguments: arguments,
        exitCode: process.terminationStatus,
        output: String(output.suffix(8_000))
    )

    guard result.succeeded else {
        throw TailOpsWormholeCommandError.failed(exitCode: result.exitCode, output: result.output)
    }

    return result
}
