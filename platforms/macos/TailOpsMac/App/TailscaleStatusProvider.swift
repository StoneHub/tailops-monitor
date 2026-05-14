import Foundation

protocol TailscaleStatusProviding: Sendable {
    func statusJSON() async throws -> Data
}

struct ProcessTailscaleStatusProvider: TailscaleStatusProviding {
    private let candidateExecutablePaths = [
        "/Applications/Tailscale.app/Contents/MacOS/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
        "/usr/bin/tailscale",
    ]

    func statusJSON() async throws -> Data {
        try await Task.detached(priority: .utility) {
            guard let executableURL = candidateExecutablePaths
                .map(URL.init(fileURLWithPath:))
                .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
            else {
                throw TailscaleStatusError.executableNotFound(candidateExecutablePaths)
            }

            let process = Process()
            let output = Pipe()
            let errorOutput = Pipe()
            process.executableURL = executableURL
            process.arguments = ["status", "--json"]
            process.standardOutput = output
            process.standardError = errorOutput

            try process.run()
            process.waitUntilExit()

            let data = output.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus == 0 {
                return data
            }

            let stderr = String(data: errorOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            throw TailscaleStatusError.commandFailed(stderr?.trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
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
