@preconcurrency import Network
import CryptoKit
import Foundation
import TailOpsCore
import TailOpsShared

struct TailOpsWormholePendingSignalPayload: Codable, Equatable, Sendable {
    let version: Int
    let messageID: String
    let pairingID: String
    let senderName: String
    let fileName: String
    let fileSizeBytes: Int64?
    let createdAt: Date
    let expiresAt: Date

    init(transfer: TailOpsWormholePendingTransfer) {
        version = 1
        messageID = transfer.id
        pairingID = transfer.pairingID
        senderName = transfer.senderName
        fileName = transfer.fileName
        fileSizeBytes = transfer.fileSizeBytes
        createdAt = transfer.createdAt
        expiresAt = transfer.expiresAt
    }
}

struct TailOpsWormholePendingSignalAcknowledgement: Codable, Equatable, Sendable {
    let messageID: String
    let acceptedAt: Date
}

final class TailOpsWormholePendingSignalServer: @unchecked Sendable {
    static let shared = TailOpsWormholePendingSignalServer()
    static let maximumHeaderBytes = 8 * 1024
    static let maximumBodyBytes = 16 * 1024
    static let maximumRequestBytes = maximumHeaderBytes + maximumBodyBytes + 4
    static let maximumConnections = 8
    static let requestTimeout: TimeInterval = 10

    private let queue = DispatchQueue(label: "dev.tailops.monitor.wormhole-pending")
    private var listener: NWListener?
    private var activeConnections = Set<ObjectIdentifier>()
    private var deadlines: [ObjectIdentifier: DispatchWorkItem] = [:]
    private let store: SharedSnapshotStore
    private let secretStore: any TailOpsWormholeSecretStoring

    init(
        store: SharedSnapshotStore = SharedSnapshotStore(),
        secretStore: any TailOpsWormholeSecretStoring = TailOpsWormholeSecretStore()
    ) {
        self.store = store
        self.secretStore = secretStore
    }

    func start() {
        guard listener == nil else { return }
        let configuration = (try? store.loadWormholeConfiguration()) ?? TailOpsWormholeConfiguration()
        guard let port = NWEndpoint.Port(rawValue: UInt16(configuration.pendingSignalPort ?? 39117)) else {
            Self.publishServiceError("The Wormhole signal port is invalid.")
            return
        }
        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    Self.publishServiceError("Wormhole signal listener failed: \(error.localizedDescription)")
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            Self.publishServiceError("Wormhole signal listener failed: \(error.localizedDescription)")
        }
    }

    private func handle(_ connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        connection.start(queue: queue)
        guard activeConnections.count < Self.maximumConnections else {
            sendResponse(status: "429 Too Many Requests", body: nil, on: connection)
            return
        }
        activeConnections.insert(identifier)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            if case .failed = state { self.finish(connection) }
            if case .cancelled = state { self.finish(connection) }
        }
        let deadline = DispatchWorkItem { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.sendResponse(status: "408 Request Timeout", body: nil, on: connection)
        }
        deadlines[identifier] = deadline
        queue.asyncAfter(deadline: .now() + Self.requestTimeout, execute: deadline)
        receiveRequest(from: connection, buffer: Data())
    }

    private func receiveRequest(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            guard error == nil else { self.finish(connection); return }
            var requestData = buffer
            if let data { requestData.append(data) }

            do {
                let expectedLength = try Self.expectedRequestLength(requestData)
                if let expectedLength {
                    guard requestData.count <= expectedLength else {
                        throw TailOpsWormholePendingSignalError.invalidRequest
                    }
                    if requestData.count == expectedLength {
                        let acknowledgement = try self.accept(requestData, now: Date())
                        let body = try Self.encoder.encode(acknowledgement)
                        self.sendResponse(status: "201 Created", body: body, on: connection)
                        return
                    }
                }
                guard !isComplete else { throw TailOpsWormholePendingSignalError.invalidRequest }
                self.receiveRequest(from: connection, buffer: requestData)
            } catch let error as TailOpsWormholePendingSignalError {
                self.sendResponse(status: error.httpStatus, body: nil, on: connection)
            } catch {
                Self.publishServiceError("Wormhole signal could not be stored: \(error.localizedDescription)")
                self.sendResponse(status: "500 Internal Server Error", body: nil, on: connection)
            }
        }
    }

    private func sendResponse(status: String, body: Data?, on connection: NWConnection) {
        let body = body ?? Data()
        let contentType = body.isEmpty ? "" : "Content-Type: application/json\r\n"
        let header = "HTTP/1.1 \(status)\r\n\(contentType)Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [weak self] _ in
            self?.finish(connection)
        })
    }

    private func finish(_ connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        deadlines.removeValue(forKey: identifier)?.cancel()
        activeConnections.remove(identifier)
        connection.cancel()
    }

    func accept(_ data: Data, now: Date) throws -> TailOpsWormholePendingSignalAcknowledgement {
        let request = try Self.parseCompleteRequest(data)
        let payload = try Self.decoder.decode(TailOpsWormholePendingSignalPayload.self, from: request.body)
        guard payload.version == 1,
              UUID(uuidString: payload.messageID) != nil,
              !payload.pairingID.isEmpty,
              !payload.senderName.isEmpty,
              !payload.fileName.isEmpty,
              payload.senderName.utf8.count <= 256,
              payload.fileName.utf8.count <= 1_024,
              payload.fileSizeBytes.map({ $0 >= 0 }) ?? true
        else { throw TailOpsWormholePendingSignalError.invalidPayload }

        let configuration = try store.loadWormholeConfiguration() ?? TailOpsWormholeConfiguration()
        guard let contact = configuration.contacts.first(where: { $0.pairingID == payload.pairingID }),
              let secret = try secretStore.secret(for: contact.id),
              Self.isValidSignature(request.signature, body: request.body, secret: secret)
        else { throw TailOpsWormholePendingSignalError.invalidSignature }

        guard payload.createdAt <= now.addingTimeInterval(120),
              payload.expiresAt > now,
              payload.expiresAt > payload.createdAt,
              payload.expiresAt.timeIntervalSince(payload.createdAt) <= 20 * 60
        else { throw TailOpsWormholePendingSignalError.invalidTime }

        var replayRecords = try store.loadWormholeSignalReplayRecords(at: now)
        guard !replayRecords.contains(where: { $0.messageID == payload.messageID }) else {
            throw TailOpsWormholePendingSignalError.replay
        }

        let incoming = TailOpsWormholePendingTransfer(
            id: payload.messageID,
            contactID: contact.id,
            pairingID: payload.pairingID,
            senderName: payload.senderName,
            fileName: payload.fileName,
            fileSizeBytes: payload.fileSizeBytes,
            direction: .incoming,
            createdAt: payload.createdAt,
            expiresAt: payload.expiresAt
        )
        var transfers = try store.loadWormholePendingTransfers()
        guard !transfers.contains(where: { $0.id == incoming.id }) else {
            throw TailOpsWormholePendingSignalError.replay
        }
        transfers.append(incoming)
        try store.saveWormholePendingTransfers(transfers)
        replayRecords.append(.init(messageID: payload.messageID, expiresAt: payload.expiresAt))
        try store.saveWormholeSignalReplayRecords(replayRecords, at: now)
        return .init(messageID: payload.messageID, acceptedAt: now)
    }

    private struct ParsedRequest { let body: Data; let signature: String }

    static func expectedRequestLength(_ data: Data) throws -> Int? {
        guard data.count <= maximumRequestBytes else { throw TailOpsWormholePendingSignalError.tooLarge }
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else {
            guard data.count <= maximumHeaderBytes else { throw TailOpsWormholePendingSignalError.tooLarge }
            return nil
        }
        guard range.lowerBound <= maximumHeaderBytes else { throw TailOpsWormholePendingSignalError.tooLarge }
        let (_, contentLength) = try parseHeader(Data(data[..<range.lowerBound]))
        return range.upperBound + contentLength
    }

    private static func parseCompleteRequest(_ data: Data) throws -> ParsedRequest {
        guard let expected = try expectedRequestLength(data), expected == data.count,
              let range = data.range(of: Data("\r\n\r\n".utf8))
        else { throw TailOpsWormholePendingSignalError.invalidRequest }
        let (headers, _) = try parseHeader(Data(data[..<range.lowerBound]))
        return ParsedRequest(body: Data(data[range.upperBound...]), signature: headers["x-tailops-signature"]!)
    }

    private static func parseHeader(_ data: Data) throws -> ([String: String], Int) {
        guard let text = String(data: data, encoding: .utf8) else { throw TailOpsWormholePendingSignalError.invalidRequest }
        let lines = text.components(separatedBy: "\r\n")
        guard lines.first == "POST /wormhole/pending HTTP/1.1" else { throw TailOpsWormholePendingSignalError.invalidRequest }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw TailOpsWormholePendingSignalError.invalidRequest }
            let name = parts[0].lowercased()
            guard !name.isEmpty, headers[name] == nil else { throw TailOpsWormholePendingSignalError.invalidRequest }
            headers[name] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        guard headers["content-type"]?.lowercased() == "application/json",
              headers["transfer-encoding"] == nil,
              let lengthText = headers["content-length"],
              !lengthText.isEmpty,
              lengthText.allSatisfy(\.isNumber),
              let length = Int(lengthText),
              (1...maximumBodyBytes).contains(length),
              let signature = headers["x-tailops-signature"],
              signature.count == 64
        else { throw TailOpsWormholePendingSignalError.invalidRequest }
        return (headers, length)
    }

    static func signature(for body: Data, secret: String) -> String {
        let digest = HMAC<SHA256>.authenticationCode(for: signedData(body), using: SymmetricKey(data: Data(secret.utf8)))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isValidSignature(_ value: String, body: Data, secret: String) -> Bool {
        guard let authenticationCode = Data(hexString: value), authenticationCode.count == 32 else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            authenticationCode,
            authenticating: signedData(body),
            using: SymmetricKey(data: Data(secret.utf8))
        )
    }

    private static func signedData(_ body: Data) -> Data { Data("tailops-pending-v1\0".utf8) + body }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }

    private static func publishServiceError(_ message: String) {
        NotificationCenter.default.post(name: .tailOpsWormholeSignalServiceFailed, object: message)
    }
}

@MainActor
struct TailOpsWormholePendingSignalClient {
    let store: SharedSnapshotStore
    let secretStore: any TailOpsWormholeSecretStoring

    init(store: SharedSnapshotStore = SharedSnapshotStore(), secretStore: any TailOpsWormholeSecretStoring = TailOpsWormholeSecretStore()) {
        self.store = store; self.secretStore = secretStore
    }

    func publish(_ transfer: TailOpsWormholePendingTransfer, to contact: TailOpsWormholeContact) async throws -> TailOpsWormholePendingSignalAcknowledgement {
        guard let nodeID = contact.tailnetNodeID, !nodeID.isEmpty else { throw TailOpsWormholePendingSignalError.noStableRoute }
        guard let snapshot = try store.load(),
              let host = snapshot.hosts.first(where: { $0.id == nodeID }),
              let address = host.primaryAddress ?? host.magicDNSName
        else { throw TailOpsWormholePendingSignalError.noStableRoute }
        guard let secret = try secretStore.secret(for: contact.id) else { throw TailOpsWormholePendingSignalError.missingSecret }
        let body = try TailOpsWormholePendingSignalServer.encoder.encode(TailOpsWormholePendingSignalPayload(transfer: transfer))
        let configuration = try store.loadWormholeConfiguration() ?? TailOpsWormholeConfiguration()
        let response = try await Self.sendRawPendingRequest(
            body: body,
            signature: TailOpsWormholePendingSignalServer.signature(for: body, secret: secret),
            address: address,
            port: configuration.pendingSignalPort ?? 39117
        )
        guard response.status == 201,
              let acknowledgement = try? TailOpsWormholePendingSignalServer.decoderForClient.decode(TailOpsWormholePendingSignalAcknowledgement.self, from: response.body),
              acknowledgement.messageID == transfer.id
        else { throw TailOpsWormholePendingSignalError.invalidAcknowledgement }
        return acknowledgement
    }

    private struct RawResponse: Sendable { let status: Int; let body: Data }

    private static func sendRawPendingRequest(body: Data, signature: String, address: String, port: Int) async throws -> RawResponse {
        try await Task.detached(priority: .utility) {
            var readRef: Unmanaged<CFReadStream>?; var writeRef: Unmanaged<CFWriteStream>?
            CFStreamCreatePairWithSocketToHost(nil, address as CFString, UInt32(port), &readRef, &writeRef)
            guard let input = readRef?.takeRetainedValue() as InputStream?,
                  let output = writeRef?.takeRetainedValue() as OutputStream?
            else { throw TailOpsWormholePendingSignalError.connectionFailed }
            input.open(); output.open(); defer { input.close(); output.close() }
            let header = "POST /wormhole/pending HTTP/1.1\r\nHost: \(address):\(port)\r\nContent-Type: application/json\r\nX-TailOps-Signature: \(signature)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            let request = [UInt8](Data(header.utf8) + body)
            let deadline = Date().addingTimeInterval(10)
            var offset = 0
            while offset < request.count, Date() < deadline {
                let count = request.withUnsafeBufferPointer { output.write($0.baseAddress!.advanced(by: offset), maxLength: request.count - offset) }
                if count < 0 { throw TailOpsWormholePendingSignalError.connectionFailed }
                if count == 0 {
                    try await Task.sleep(for: .milliseconds(10))
                } else {
                    offset += count
                }
            }
            guard offset == request.count else { throw TailOpsWormholePendingSignalError.timeout }
            var response = Data(); var buffer = [UInt8](repeating: 0, count: 2_048)
            while Date() < deadline, response.count <= 6 * 1_024 {
                if input.hasBytesAvailable {
                    let count = input.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw TailOpsWormholePendingSignalError.connectionFailed }
                    if count == 0 { break }
                    response.append(contentsOf: buffer.prefix(count))
                    if Self.responseIsComplete(response) { break }
                } else if input.streamStatus == .atEnd { break }
                else { try await Task.sleep(for: .milliseconds(10)) }
            }
            guard response.count <= 6 * 1_024 else { throw TailOpsWormholePendingSignalError.invalidAcknowledgement }
            return try Self.parseResponse(response)
        }.value
    }

    private nonisolated static func responseIsComplete(_ data: Data) -> Bool {
        guard let range = data.range(of: Data("\r\n\r\n".utf8)), range.lowerBound <= 4 * 1_024,
              let header = String(data: data[..<range.lowerBound], encoding: .utf8),
              let lengthLine = header.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }),
              let length = Int(lengthLine.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)),
              (0...2 * 1_024).contains(length)
        else { return false }
        return data.count == range.upperBound + length
    }

    private nonisolated static func parseResponse(_ data: Data) throws -> RawResponse {
        guard responseIsComplete(data), let range = data.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: data[..<range.lowerBound], encoding: .utf8),
              let statusText = header.components(separatedBy: "\r\n").first,
              statusText.hasPrefix("HTTP/1.1 "),
              let status = Int(statusText.split(separator: " ")[1]),
              Data(data[range.upperBound...]).count <= 2 * 1_024,
              status != 201 || header.components(separatedBy: "\r\n").contains(where: {
                  $0.lowercased() == "content-type: application/json"
              })
        else { throw TailOpsWormholePendingSignalError.invalidAcknowledgement }
        return RawResponse(status: status, body: Data(data[range.upperBound...]))
    }
}

enum TailOpsWormholePendingSignalError: LocalizedError {
    case invalidRequest, tooLarge, invalidPayload, invalidSignature, invalidTime, replay
    case noStableRoute, missingSecret, connectionFailed, timeout, invalidAcknowledgement

    var httpStatus: String {
        switch self {
        case .tooLarge: "413 Payload Too Large"
        case .replay: "409 Conflict"
        case .invalidSignature, .invalidTime: "403 Forbidden"
        default: "400 Bad Request"
        }
    }
    var errorDescription: String? {
        switch self {
        case .noStableRoute: "Choose a specific Tailnet peer for this Wormhole pairing."
        case .missingSecret: "The Wormhole setup secret is unavailable in Keychain."
        case .connectionFailed: "The paired Mac could not be reached."
        case .timeout: "The paired Mac did not acknowledge the notification in time."
        case .invalidAcknowledgement: "The paired Mac returned an invalid notification acknowledgement."
        case .replay: "This Wormhole notification was already accepted."
        default: "The Wormhole notification was rejected."
        }
    }
}

extension Notification.Name {
    static let tailOpsWormholeSignalServiceFailed = Notification.Name("dev.tailops.monitor.wormhole-signal-failed")
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var result = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            result.append(byte); index = next
        }
        self = result
    }
}

private extension TailOpsWormholePendingSignalServer {
    static var decoderForClient: JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
}
