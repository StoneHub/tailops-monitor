@preconcurrency import Network
import CryptoKit
import Foundation
import TailOpsCore
import TailOpsShared

private struct TailOpsWormholePendingSignalPayload: Codable, Sendable {
    let transfer: TailOpsWormholePendingTransfer
}

final class TailOpsWormholePendingSignalServer: @unchecked Sendable {
    static let shared = TailOpsWormholePendingSignalServer()

    private let queue = DispatchQueue(label: "dev.tailops.monitor.wormhole-pending")
    private var listener: NWListener?
    private let store = SharedSnapshotStore()

    private init() {}

    func start() {
        guard listener == nil else { return }

        let configuration = (try? store.loadWormholeConfiguration()) ?? TailOpsWormholeConfiguration()
        let portValue = UInt16(configuration.pendingSignalPort ?? 39117)
        guard let port = NWEndpoint.Port(rawValue: portValue),
              let listener = try? NWListener(using: .tcp, on: port)
        else {
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(from: connection, buffer: Data())
    }

    private func receiveRequest(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            guard error == nil else {
                connection.cancel()
                return
            }

            var requestData = buffer
            if let data {
                requestData.append(data)
            }

            guard !requestData.isEmpty else {
                connection.cancel()
                return
            }

            guard Self.isCompleteRequest(requestData) else {
                if isComplete {
                    self.sendResponse("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n", on: connection)
                    return
                }
                self.receiveRequest(from: connection, buffer: requestData)
                return
            }

            let responseStatus: String
            do {
                try self.accept(requestData)
                responseStatus = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n"
            } catch {
                responseStatus = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n"
            }

            self.sendResponse(responseStatus, on: connection)
        }
    }

    private func sendResponse(_ responseStatus: String, on connection: NWConnection) {
        connection.send(content: Data(responseStatus.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func accept(_ data: Data) throws {
        let separator = Data("\r\n\r\n".utf8)
        guard let separatorRange = data.range(of: separator),
              let headerText = String(data: data[..<separatorRange.lowerBound], encoding: .utf8),
              headerText.hasPrefix("POST /wormhole/pending ")
        else {
            throw TailOpsWormholePendingSignalError.invalidRequest
        }

        let headers = Self.headers(from: headerText)
        guard let signature = headers["x-tailops-signature"] else {
            throw TailOpsWormholePendingSignalError.invalidSignature
        }

        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        let bodyStart = separatorRange.upperBound
        let body = data[bodyStart..<min(bodyStart + contentLength, data.count)]
        let bodyData = Data(body)
        let payload = try Self.decoder.decode(TailOpsWormholePendingSignalPayload.self, from: bodyData)

        let configuration = (try? store.loadWormholeConfiguration()) ?? TailOpsWormholeConfiguration()
        guard let contact = configuration.contacts.first(where: { $0.pairingID == payload.transfer.pairingID }),
              Self.signature(for: bodyData, secret: contact.sharedSecret) == signature
        else {
            throw TailOpsWormholePendingSignalError.invalidSignature
        }

        let incoming = TailOpsWormholePendingTransfer(
            id: payload.transfer.id,
            contactID: contact.id,
            pairingID: payload.transfer.pairingID,
            senderName: payload.transfer.senderName,
            fileName: payload.transfer.fileName,
            fileSizeBytes: payload.transfer.fileSizeBytes,
            code: payload.transfer.code,
            direction: .incoming,
            createdAt: payload.transfer.createdAt,
            expiresAt: payload.transfer.expiresAt
        )

        var transfers = try store.loadWormholePendingTransfers()
        transfers.removeAll { $0.id == incoming.id }
        transfers.append(incoming)
        try store.saveWormholePendingTransfers(transfers)
    }

    private static func headers(from headerText: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            headers[parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return headers
    }

    private static func isCompleteRequest(_ data: Data) -> Bool {
        let separator = Data("\r\n\r\n".utf8)
        guard let separatorRange = data.range(of: separator),
              let headerText = String(data: data[..<separatorRange.lowerBound], encoding: .utf8)
        else {
            return false
        }

        let headers = headers(from: headerText)
        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        let bodyStart = separatorRange.upperBound
        return data.count >= bodyStart + contentLength
    }

    fileprivate static func signature(for data: Data, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let digest = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

@MainActor
struct TailOpsWormholePendingSignalClient {
    let store: SharedSnapshotStore

    init(store: SharedSnapshotStore = SharedSnapshotStore()) {
        self.store = store
    }

    func publish(_ transfer: TailOpsWormholePendingTransfer, to contact: TailOpsWormholeContact) async {
        guard let host = destinationHost(for: contact),
              let address = host.primaryAddress ?? host.magicDNSName
        else {
            return
        }

        let payload = TailOpsWormholePendingSignalPayload(transfer: transfer)
        guard let body = try? TailOpsWormholePendingSignalServer.encoder.encode(payload) else { return }
        let configuration = (try? store.loadWormholeConfiguration()) ?? TailOpsWormholeConfiguration()
        let port = configuration.pendingSignalPort ?? 39117

        await Self.sendRawPendingRequest(
            body: body,
            signature:
            TailOpsWormholePendingSignalServer.signature(for: body, secret: contact.sharedSecret),
            address: address,
            port: port
        )
    }

    private func destinationHost(for contact: TailOpsWormholeContact) -> TailnetHost? {
        guard let snapshot = try? store.load() else { return nil }
        return snapshot.hosts.first { host in
            let hostTokens = [
                host.name,
                host.magicDNSName ?? "",
                host.primaryAddress ?? ""
            ].map(Self.normalized)
            let contactTokens = [
                contact.displayName,
                contact.pairingID
            ].map(Self.normalized)

            return contactTokens.contains { contactToken in
                guard contactToken.count >= 3 else { return false }
                return hostTokens.contains { hostToken in
                    hostToken.contains(contactToken) || contactToken.contains(hostToken)
                }
            }
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func sendRawPendingRequest(
        body: Data,
        signature: String,
        address: String,
        port: Int
    ) async {
        await Task.detached(priority: .utility) {
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?
            CFStreamCreatePairWithSocketToHost(nil, address as CFString, UInt32(port), &readStream, &writeStream)
            guard let stream = writeStream?.takeRetainedValue() as OutputStream? else { return }

            let header = [
                "POST /wormhole/pending HTTP/1.1",
                "Host: \(address):\(port)",
                "Content-Type: application/json",
                "X-TailOps-Signature: \(signature)",
                "Content-Length: \(body.count)",
                "Connection: close",
                "",
                ""
            ].joined(separator: "\r\n")
            var requestData = Data(header.utf8)
            requestData.append(body)

            stream.open()
            defer { stream.close() }

            var offset = 0
            let bytes = [UInt8](requestData)
            while offset < bytes.count {
                let written = bytes.withUnsafeBufferPointer { pointer in
                    stream.write(pointer.baseAddress!.advanced(by: offset), maxLength: bytes.count - offset)
                }
                guard written > 0 else { break }
                offset += written
            }
        }.value
    }
}

private enum TailOpsWormholePendingSignalError: Error {
    case invalidRequest
    case invalidSignature
}
