import Foundation

public struct TaildropTarget: Codable, Equatable, Identifiable, Sendable {
    public let address: String
    public let name: String
    public let detail: String?
    public let isAvailable: Bool

    public var id: String {
        address
    }

    public init(address: String, name: String, detail: String? = nil, isAvailable: Bool = true) {
        self.address = address
        self.name = name
        self.detail = detail
        self.isAvailable = isAvailable
    }
}

public struct TaildropTargetsParser: Sendable {
    public init() {}

    public func parse(_ output: String) -> [TaildropTarget] {
        output
            .split(separator: "\n")
            .compactMap { Self.parseLine(String($0)) }
    }

    private static func parseLine(_ line: String) -> TaildropTarget? {
        let fields = line
            .split(separator: "\t", omittingEmptySubsequences: false)
            .map(String.init)

        guard fields.count >= 2 else { return nil }
        let detail = fields.count >= 3 && !fields[2].isEmpty ? fields[2] : nil
        return TaildropTarget(
            address: fields[0],
            name: TailnetDisplayName.cleaned(fields[1]) ?? fields[1],
            detail: detail,
            isAvailable: !(detail?.localizedCaseInsensitiveContains("offline") ?? false)
        )
    }
}
