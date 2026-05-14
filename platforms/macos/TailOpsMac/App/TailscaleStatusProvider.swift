import Foundation

protocol TailscaleStatusProviding: Sendable {
    func statusJSON() async throws -> Data
}

struct ProcessTailscaleStatusProvider: TailscaleStatusProviding {
    func statusJSON() async throws -> Data {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            let errorOutput = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["tailscale", "status", "--json"]
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
    case commandFailed(String?)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message?.isEmpty == false ? message : "tailscale status --json failed"
        }
    }
}
