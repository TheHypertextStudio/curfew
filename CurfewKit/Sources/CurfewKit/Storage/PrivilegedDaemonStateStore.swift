import Foundation

public struct PrivilegedDaemonStateStore: Sendable {
    public static let productionURL = URL(
        fileURLWithPath: "/Library/Application Support/Curfew/lockout-state.json"
    )

    public let stateURL: URL

    public init(stateURL: URL = Self.productionURL) {
        self.stateURL = stateURL
    }

    public func load() throws -> PrivilegedDaemonStatus? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: stateURL)
        return try Self.decoder.decode(PrivilegedDaemonStatus.self, from: data)
    }

    public func save(_ status: PrivilegedDaemonStatus) throws {
        let directory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: directory.path
        )
        let data = try Self.encoder.encode(status)
        try data.write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stateURL.path
        )
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return }
        try FileManager.default.removeItem(at: stateURL)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
