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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else {
                connection.cancel()
                return
            }

            let responseStatus: String
            do {
                try self.accept(data)
                responseStatus = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n"
            } catch {
                responseStatus = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n"
            }

            connection.send(content: Data(responseStatus.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func accept(_ data: Data) throws {
        guard let request = String(data: data, encoding: .utf8),
              request.hasPrefix("POST /wormhole/pending "),
              let headerRange = request.range(of: "\r\n\r\n")
        else {
            throw TailOpsWormholePendingSignalError.invalidRequest
        }

        let headerText = String(request[..<headerRange.lowerBound])
        let headers = Self.headers(from: headerText)
        guard let signature = headers["x-tailops-signature"] else {
            throw TailOpsWormholePendingSignalError.invalidSignature
        }

        let bodyStart = request.distance(from: request.startIndex, to: headerRange.upperBound)
        let body = data.dropFirst(bodyStart)
        let payload = try Self.decoder.decode(TailOpsWormholePendingSignalPayload.self, from: Data(body))

        let configuration = (try? store.loadWormholeConfiguration()) ?? TailOpsWormholeConfiguration()
        guard let contact = configuration.contacts.first(where: { $0.pairingID == payload.transfer.pairingID }),
              Self.signature(for: Data(body), secret: contact.sharedSecret) == signature
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
        for line in headerText.split(separator: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            headers[parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return headers
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
              let address = host.primaryAddress ?? host.magicDNSName,
              let url = pendingURL(address: address)
        else {
            return
        }

        let payload = TailOpsWormholePendingSignalPayload(transfer: transfer)
        guard let body = try? TailOpsWormholePendingSignalServer.encoder.encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            TailOpsWormholePendingSignalServer.signature(for: body, secret: contact.sharedSecret),
            forHTTPHeaderField: "X-TailOps-Signature"
        )
        request.httpBody = body

        _ = try? await URLSession.shared.data(for: request)
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

    private func pendingURL(address: String) -> URL? {
        let configuration = (try? store.loadWormholeConfiguration()) ?? TailOpsWormholeConfiguration()
        let port = configuration.pendingSignalPort ?? 39117
        let host = address.contains(":") && !address.hasPrefix("[") ? "[\(address)]" : address
        return URL(string: "http://\(host):\(port)/wormhole/pending")
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

private enum TailOpsWormholePendingSignalError: Error {
    case invalidRequest
    case invalidSignature
}
