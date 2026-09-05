import CryptoKit
import Foundation

/// The coordinator-signed envelope delivered to a native Curfew device.
public struct SignedRemoteLockoutCommandEnvelope: Codable, Equatable, Sendable {
    public let compactJWS: String

    public init(compactJWS: String) {
        self.compactJWS = compactJWS
    }

    private enum CodingKeys: String, CodingKey {
        case compactJWS = "compactJws"
    }
}

/// Platform-neutral handoff from an account transport to the privileged
/// enforcement backend. The app preserves the signed coordinator envelope
/// byte-for-byte and never turns it into an authenticated command itself.
public struct PendingRemoteCommandDelivery: Codable, Equatable, Sendable {
    public let cursor: String
    public let envelope: SignedRemoteLockoutCommandEnvelope

    public init(cursor: String, envelope: SignedRemoteLockoutCommandEnvelope) {
        self.cursor = cursor
        self.envelope = envelope
    }
}

/// User-writable, opaque command spool. Authority is deliberately absent from
/// this type: only the privileged backend may verify and apply an envelope.
public struct RemoteCommandInboxStore: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func stage(_ delivery: PendingRemoteCommandDelivery) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = fileURL(for: delivery.cursor)
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(delivery).write(to: destination, options: .atomic)
    }

    public func pendingDeliveries() throws -> [PendingRemoteCommandDelivery] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { file in
            try JSONDecoder().decode(
                PendingRemoteCommandDelivery.self,
                from: Data(contentsOf: file)
            )
        }
    }

    public func remove(cursor: String) throws {
        let destination = fileURL(for: cursor)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    private func fileURL(for cursor: String) -> URL {
        let digest = SHA256.hash(data: Data(cursor.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appendingPathComponent("\(digest).json")
    }
}

/// Exact terminal-result identity used for the app-to-daemon publication
/// acknowledgement. It contains no authority to alter enforcement state.
public struct RemoteCommandResultIdentity: Codable, Equatable, Sendable {
    public let commandID: UUID
    public let deviceID: UUID
    public let sequence: Int64

    public init(commandID: UUID, deviceID: UUID, sequence: Int64) {
        self.commandID = commandID
        self.deviceID = deviceID
        self.sequence = sequence
    }

    public init(result: RemoteCommandResult) {
        self.init(
            commandID: result.commandID,
            deviceID: result.deviceID,
            sequence: result.sequence
        )
    }

    private enum CodingKeys: String, CodingKey {
        case commandID = "commandId"
        case deviceID = "deviceId"
        case sequence
    }
}

/// Durable, platform-neutral bridge between the privileged enforcement
/// backend and the user-session transport. The daemon publishes a read-only
/// snapshot; the app writes one exact acknowledgement file only after the
/// coordinator accepts the corresponding result.
public struct RemoteCommandResultExchangeStore: Sendable {
    public let resultsURL: URL
    public let acknowledgementsDirectoryURL: URL

    public init(resultsURL: URL, acknowledgementsDirectoryURL: URL) {
        self.resultsURL = resultsURL
        self.acknowledgementsDirectoryURL = acknowledgementsDirectoryURL
    }

    public func publish(_ results: [RemoteCommandResult]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: resultsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        let data = try Self.encoder.encode(results)
        try data.write(to: resultsURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: resultsURL.path
        )
    }

    public func pendingResults() throws -> [RemoteCommandResult] {
        guard FileManager.default.fileExists(atPath: resultsURL.path) else { return [] }
        return try Self.decoder.decode(
            [RemoteCommandResult].self,
            from: Data(contentsOf: resultsURL)
        )
    }

    public func acknowledge(_ identity: RemoteCommandResultIdentity) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: acknowledgementsDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = acknowledgementURL(identity)
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        try Self.encoder.encode(identity).write(to: destination, options: .atomic)
    }

    public func pendingAcknowledgements() throws -> [RemoteCommandResultIdentity] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: acknowledgementsDirectoryURL.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(
            at: acknowledgementsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        return try files.compactMap { file in
            do {
                return try Self.decoder.decode(
                    RemoteCommandResultIdentity.self,
                    from: Data(contentsOf: file)
                )
            } catch {
                try fileManager.removeItem(at: file)
                return nil
            }
        }
    }

    public func removeAcknowledgement(_ identity: RemoteCommandResultIdentity) throws {
        let destination = acknowledgementURL(identity)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    private func acknowledgementURL(_ identity: RemoteCommandResultIdentity) -> URL {
        let key = "\(identity.deviceID.uuidString.lowercased()):\(identity.commandID.uuidString.lowercased()):\(identity.sequence)"
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return acknowledgementsDirectoryURL.appendingPathComponent("\(digest).json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
