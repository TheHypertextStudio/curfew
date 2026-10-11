import Foundation

public struct PrivilegedDaemonStateStore: Sendable {
    public static let productionURL = stateURL(for: .production)

    public static func stateURL(for flavor: CurfewFlavor) -> URL {
        SharedPaths.privilegedApplicationSupport(for: flavor)
            .appendingPathComponent("lockout-state.json")
    }

    public let stateURL: URL

    public init(stateURL: URL = Self.stateURL(for: .current)) {
        self.stateURL = stateURL
    }

    public func load() throws -> PrivilegedDaemonStatus? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return nil
        }
        guard let data = try BoundedRegularFileReader.read(stateURL, maximumBytes: 1024 * 1024)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let control = try? Self.decoder.decode(AuthenticatedDaemonControl.self, from: data) {
            return control.localStatus
        }
        return try Self.decoder.decode(PrivilegedDaemonStatus.self, from: data)
    }

    public func loadControl() throws -> AuthenticatedDaemonControl? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        guard let data = try BoundedRegularFileReader.read(stateURL, maximumBytes: 1024 * 1024)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let control = try? Self.decoder
            .decode(AuthenticatedDaemonControl.self, from: data) {
            return control
        }
        return try AuthenticatedDaemonControl(persisted: Self.decoder.decode(
            PrivilegedDaemonStatus.self,
            from: data
        ))
    }

    public func saveControl(_ control: AuthenticatedDaemonControl) throws {
        try write(Self.encoder.encode(control))
    }

    public func save(_ status: PrivilegedDaemonStatus) throws {
        try write(Self.encoder.encode(status))
    }

    private func write(_ data: Data) throws {
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
