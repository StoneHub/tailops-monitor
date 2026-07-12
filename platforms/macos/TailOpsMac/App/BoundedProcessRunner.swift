import Darwin
import Foundation

struct BoundedProcessResult: Sendable {
    let terminationStatus: Int32
    let stdout: Data
    let stderr: Data
}

enum BoundedProcessRunnerError: LocalizedError {
    case launchFailed(String)
    case timedOut(executable: String, seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .timedOut(let executable, let seconds):
            return "\(executable) did not finish within \(Int(seconds)) seconds."
        }
    }
}

/// Runs a child process without allowing its pipes, runtime, or captured output to grow unbounded.
struct BoundedProcessRunner: Sendable {
    private static let readChunkSize = 64 * 1_024

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval,
        maximumStandardOutputBytes: Int,
        maximumStandardErrorBytes: Int
    ) async throws -> BoundedProcessResult {
        precondition(timeout > 0)
        precondition(maximumStandardOutputBytes > 0)
        precondition(maximumStandardErrorBytes > 0)

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let execution = ProcessExecution(
            process: process,
            timeoutError: .timedOut(
                executable: executableURL.lastPathComponent,
                seconds: timeout
            )
        )

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardOutput = standardOutput
        process.standardError = standardError

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()

            do {
                try execution.launch()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw BoundedProcessRunnerError.launchFailed(error.localizedDescription)
            }

            // The child inherited duplicate write descriptors. Closing the parent's copies lets
            // the readers observe EOF immediately when the child exits.
            try? standardOutput.fileHandleForWriting.close()
            try? standardError.fileHandleForWriting.close()
            execution.scheduleTimeout(after: timeout)

            async let capturedStandardOutput = Self.capture(
                standardOutput.fileHandleForReading,
                maximumBytes: maximumStandardOutputBytes
            )
            async let capturedStandardError = Self.capture(
                standardError.fileHandleForReading,
                maximumBytes: maximumStandardErrorBytes
            )

            do {
                let terminationStatus = try await execution.terminationStatus()
                return try await BoundedProcessResult(
                    terminationStatus: terminationStatus,
                    stdout: capturedStandardOutput,
                    stderr: capturedStandardError
                )
            } catch {
                execution.cancel()
                _ = try? await (capturedStandardOutput, capturedStandardError)
                throw error
            }
        } onCancel: {
            execution.cancel()
        }
    }

    private static func capture(_ handle: FileHandle, maximumBytes: Int) async throws -> Data {
        try await Task.detached(priority: .utility) {
            defer { try? handle.close() }
            var captured = Data()

            while let chunk = try handle.read(upToCount: readChunkSize), !chunk.isEmpty {
                captured.append(chunk)
                if captured.count > maximumBytes {
                    captured.removeFirst(captured.count - maximumBytes)
                }
            }

            return captured
        }.value
    }
}

private final class ProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let timeoutError: BoundedProcessRunnerError
    private var continuation: CheckedContinuation<Int32, Error>?
    private var completedResult: Result<Int32, Error>?
    private var requestedError: Error?

    init(process: Process, timeoutError: BoundedProcessRunnerError) {
        self.process = process
        self.timeoutError = timeoutError
    }

    func launch() throws {
        lock.lock()
        defer { lock.unlock() }

        if requestedError is CancellationError {
            throw CancellationError()
        }

        process.terminationHandler = { [weak self] process in
            self?.didTerminate(with: process.terminationStatus)
        }
        try process.run()
    }

    func scheduleTimeout(after timeout: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.requestTermination(with: self?.timeoutError)
        }
    }

    func terminationStatus() async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let completedResult {
                lock.unlock()
                continuation.resume(with: completedResult)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func cancel() {
        requestTermination(with: CancellationError())
    }

    private func requestTermination(with error: Error?) {
        guard let error else { return }

        lock.lock()
        guard completedResult == nil, requestedError == nil else {
            lock.unlock()
            return
        }
        requestedError = error
        let shouldTerminate = process.isRunning
        let processIdentifier = process.processIdentifier
        lock.unlock()

        guard shouldTerminate else { return }
        process.terminate()

        // Some tools ignore SIGTERM. Escalate so the advertised deadline remains bounded.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.isStillRunning else { return }
            Darwin.kill(processIdentifier, SIGKILL)
        }
    }

    private var isStillRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completedResult == nil && process.isRunning
    }

    private func didTerminate(with status: Int32) {
        lock.lock()
        guard completedResult == nil else {
            lock.unlock()
            return
        }

        let result: Result<Int32, Error>
        if let requestedError {
            result = .failure(requestedError)
        } else {
            result = .success(status)
        }
        completedResult = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}
