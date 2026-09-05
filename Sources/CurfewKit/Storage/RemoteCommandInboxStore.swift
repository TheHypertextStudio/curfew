import CryptoKit
import Darwin
import Foundation

public enum RemoteCommandResultExchangeError: Error, Equatable {
    case resultIdentityMismatch
    case unsafeFilesystemEntry
}

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

/// Opaque coordinator-signed proof that one exact terminal result was
/// accepted. The user-session app may persist it, but only the privileged
/// verifier may treat it as authority to remove a daemon outbox entry.
public struct CoordinatorSignedRemoteCommandResultReceiptEnvelope: Codable, Equatable, Sendable {
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let directory = try RemoteCommandExchangeFilesystem.openDirectory(
            directoryURL,
            requiredOwnerUserID: nil
        )
        defer { close(directory) }
        try RemoteCommandExchangeFilesystem.writeAtomically(
            encoder.encode(delivery),
            named: fileURL(for: delivery.cursor).lastPathComponent,
            in: directory,
            permissions: 0o600,
            replaceExisting: false
        )
    }

    public func pendingDeliveries(maximumCount: Int = 32) throws -> [PendingRemoteCommandDelivery] {
        guard maximumCount > 0,
              let directory = try RemoteCommandExchangeFilesystem.openDirectoryIfPresent(
                  directoryURL,
                  requiredOwnerUserID: nil,
                  forEnumeration: true
              )
        else { return [] }
        defer { close(directory) }
        let names = try RemoteCommandExchangeFilesystem.entryNames(
            in: directory,
            maximumCount: maximumCount + 1
        )
        guard names.count <= maximumCount else {
            // The coordinator delivers at most one complete daemon batch. An
            // oversized user-writable spool is therefore untrusted overflow,
            // not a partial batch that may be safely sequence-sorted. Drain a
            // bounded chunk and let the coordinator redeliver unacknowledged
            // commands instead of doing unbounded work every daemon tick.
            try RemoteCommandExchangeFilesystem.quarantine(
                names: names,
                from: directory,
                beside: directoryURL
            )
            return []
        }
        return names.compactMap { name in
            do {
                guard name.range(
                    of: "^[a-f0-9]{64}\\.json$",
                    options: .regularExpression
                ) != nil else {
                    try RemoteCommandExchangeFilesystem.remove(named: name, in: directory)
                    return nil
                }
                guard let data = try RemoteCommandExchangeFilesystem.readRegularFileIfPresent(
                    named: name,
                    in: directory,
                    maximumBytes: 1_048_576
                ) else { return nil }
                let delivery = try JSONDecoder().decode(
                    PendingRemoteCommandDelivery.self,
                    from: data
                )
                guard name == entryName(for: delivery.cursor) else {
                    throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
                }
                return delivery
            } catch {
                try? RemoteCommandExchangeFilesystem.remove(named: name, in: directory)
                return nil
            }
        }
    }

    public func remove(cursor: String) throws {
        guard let directory = try RemoteCommandExchangeFilesystem.openDirectoryIfPresent(
            directoryURL,
            requiredOwnerUserID: nil
        ) else { return }
        defer { close(directory) }
        try RemoteCommandExchangeFilesystem.remove(
            named: fileURL(for: cursor).lastPathComponent,
            in: directory
        )
    }

    private func fileURL(for cursor: String) -> URL {
        directoryURL.appendingPathComponent(entryName(for: cursor))
    }

    private func entryName(for cursor: String) -> String {
        let digest = SHA256.hash(data: Data(cursor.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(digest).json"
    }
}

/// Exact terminal-result identity returned only after a coordinator receipt
/// has been cryptographically verified.
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
/// snapshot; the app writes the coordinator's signed receipt to the one exact
/// result-derived filename after acceptance.
public struct RemoteCommandResultExchangeStore: Sendable {
    public let resultsURL: URL
    public let acknowledgementsDirectoryURL: URL
    public let requiredDirectoryOwnerUserID: UInt32?

    public init(
        resultsURL: URL,
        acknowledgementsDirectoryURL: URL,
        requiredDirectoryOwnerUserID: UInt32? = nil
    ) {
        self.resultsURL = resultsURL
        self.acknowledgementsDirectoryURL = acknowledgementsDirectoryURL
        self.requiredDirectoryOwnerUserID = requiredDirectoryOwnerUserID
    }

    public func publish(_ results: [RemoteCommandResult]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: resultsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try fileManager.createDirectory(
            at: acknowledgementsDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o733]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o733],
            ofItemAtPath: acknowledgementsDirectoryURL.path
        )
        let acknowledgementsDirectory = try RemoteCommandExchangeFilesystem.openDirectory(
            acknowledgementsDirectoryURL,
            requiredOwnerUserID: requiredDirectoryOwnerUserID
        )
        close(acknowledgementsDirectory)
        let data = try Self.encoder.encode(results)
        let directory = try RemoteCommandExchangeFilesystem.openDirectory(
            resultsURL.deletingLastPathComponent(),
            requiredOwnerUserID: requiredDirectoryOwnerUserID
        )
        defer { close(directory) }
        try RemoteCommandExchangeFilesystem.writeAtomically(
            data,
            named: resultsURL.lastPathComponent,
            in: directory,
            permissions: 0o644
        )
    }

    public func pendingResults() throws -> [RemoteCommandResult] {
        guard let directory = try RemoteCommandExchangeFilesystem.openDirectoryIfPresent(
            resultsURL.deletingLastPathComponent(),
            requiredOwnerUserID: requiredDirectoryOwnerUserID
        ) else { return [] }
        defer { close(directory) }
        guard let data = try RemoteCommandExchangeFilesystem.readRegularFileIfPresent(
            named: resultsURL.lastPathComponent,
            in: directory,
            maximumBytes: 1_048_576
        ) else { return [] }
        return try Self.decoder.decode(
            [RemoteCommandResult].self,
            from: data
        )
    }

    public func recordReceipt(
        _ receipt: CoordinatorSignedRemoteCommandResultReceiptEnvelope,
        for result: RemoteCommandResult
    ) throws {
        try FileManager.default.createDirectory(
            at: acknowledgementsDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o733]
        )
        let directory = try RemoteCommandExchangeFilesystem.openDirectory(
            acknowledgementsDirectoryURL,
            requiredOwnerUserID: requiredDirectoryOwnerUserID
        )
        defer { close(directory) }
        try RemoteCommandExchangeFilesystem.writeAtomically(
            Self.encoder.encode(receipt),
            named: receiptURL(for: result).lastPathComponent,
            in: directory,
            permissions: 0o600
        )
    }

    /// Reads only the filename derived from the pending result. Directory
    /// enumeration would let unrelated user-created entries influence daemon
    /// work. Unsafe or malformed exact candidates are removed and ignored.
    public func pendingReceipt(
        for result: RemoteCommandResult
    ) throws -> CoordinatorSignedRemoteCommandResultReceiptEnvelope? {
        guard let directory = try RemoteCommandExchangeFilesystem.openDirectoryIfPresent(
            acknowledgementsDirectoryURL,
            requiredOwnerUserID: requiredDirectoryOwnerUserID
        ) else { return nil }
        defer { close(directory) }
        let name = receiptURL(for: result).lastPathComponent
        do {
            guard let data = try RemoteCommandExchangeFilesystem.readRegularFileIfPresent(
                named: name,
                in: directory,
                maximumBytes: 65536
            ) else { return nil }
            return try Self.decoder.decode(
                CoordinatorSignedRemoteCommandResultReceiptEnvelope.self,
                from: data
            )
        } catch {
            try? RemoteCommandExchangeFilesystem.remove(named: name, in: directory)
            return nil
        }
    }

    public func removeReceipt(for result: RemoteCommandResult) throws {
        guard let directory = try RemoteCommandExchangeFilesystem.openDirectoryIfPresent(
            acknowledgementsDirectoryURL,
            requiredOwnerUserID: requiredDirectoryOwnerUserID
        ) else { return }
        defer { close(directory) }
        try RemoteCommandExchangeFilesystem.remove(
            named: receiptURL(for: result).lastPathComponent,
            in: directory
        )
    }

    public func receiptURL(for result: RemoteCommandResult) -> URL {
        receiptURL(RemoteCommandResultIdentity(result: result))
    }

    private func receiptURL(_ identity: RemoteCommandResultIdentity) -> URL {
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

private enum RemoteCommandExchangeFilesystem {
    static func openDirectory(
        _ url: URL,
        requiredOwnerUserID: UInt32?,
        forEnumeration: Bool = false
    ) throws -> Int32 {
        let access = forEnumeration ? O_RDONLY : O_SEARCH
        let descriptor = Darwin.open(url.path, access | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFDIR,
              requiredOwnerUserID == nil || metadata.st_uid == requiredOwnerUserID
        else {
            close(descriptor)
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        return descriptor
    }

    static func openDirectoryIfPresent(
        _ url: URL,
        requiredOwnerUserID: UInt32?,
        forEnumeration: Bool = false
    ) throws -> Int32? {
        var metadata = stat()
        if lstat(url.path, &metadata) != 0 {
            if errno == ENOENT {
                return nil
            }
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        guard metadata.st_mode & S_IFMT == S_IFDIR else {
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        return try openDirectory(
            url,
            requiredOwnerUserID: requiredOwnerUserID,
            forEnumeration: forEnumeration
        )
    }

    static func entryNames(in directory: Int32, maximumCount: Int) throws -> [String] {
        guard maximumCount > 0 else { return [] }
        let duplicate = dup(directory)
        guard duplicate >= 0, let stream = fdopendir(duplicate) else {
            if duplicate >= 0 {
                close(duplicate)
            }
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        defer { closedir(stream) }
        var names: [String] = []
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name != ".", name != ".." {
                names.append(name)
                if names.count == maximumCount {
                    break
                }
            }
        }
        return names
    }

    static func quarantine(names: [String], from directory: Int32, beside url: URL) throws {
        guard !names.isEmpty else { return }
        let parentURL = url.deletingLastPathComponent()
        let parent = try openDirectory(parentURL, requiredOwnerUserID: nil)
        defer { close(parent) }

        var quarantineName: String?
        for _ in 0 ..< 8 {
            let candidate = ".remote-command-quarantine-\(UUID().uuidString.lowercased())"
            let status = candidate.withCString { mkdirat(parent, $0, 0o700) }
            if status == 0 {
                quarantineName = candidate
                break
            }
            guard errno == EEXIST else {
                throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
            }
        }
        guard let quarantineName else {
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        let quarantine = quarantineName.withCString {
            openat(parent, $0, O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard quarantine >= 0 else {
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        defer { close(quarantine) }

        for name in names {
            let destination = UUID().uuidString.lowercased()
            let status = name.withCString { sourceName in
                destination.withCString { destinationName in
                    renameat(directory, sourceName, quarantine, destinationName)
                }
            }
            guard status == 0 || errno == ENOENT else {
                throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
            }
        }
    }

    static func readRegularFileIfPresent(
        named name: String,
        in directory: Int32,
        maximumBytes: Int
    ) throws -> Data? {
        let descriptor = name.withCString {
            openat(directory, $0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            if errno == ENOENT {
                return nil
            }
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1
        else {
            close(descriptor)
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        defer { close(descriptor) }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count == 0 {
                return result
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
            }
            guard result.count + count <= maximumBytes else {
                throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
            }
            result.append(buffer, count: count)
        }
    }

    static func writeAtomically(
        _ data: Data,
        named name: String,
        in directory: Int32,
        permissions: mode_t,
        replaceExisting: Bool = true
    ) throws {
        if !replaceExisting {
            var metadata = stat()
            let status = name.withCString { fstatat(directory, $0, &metadata, AT_SYMLINK_NOFOLLOW) }
            if status == 0 {
                return
            }
            guard errno == ENOENT else {
                throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
            }
        }
        let temporary = ".curfew-\(UUID().uuidString.lowercased()).tmp"
        let descriptor = temporary.withCString {
            openat(
                directory,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                permissions
            )
        }
        guard descriptor >= 0 else {
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        var completed = false
        defer {
            close(descriptor)
            if !completed {
                temporary.withCString { _ = unlinkat(directory, $0, 0) }
            }
        }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    bytes.count - offset
                )
                guard count > 0 else {
                    throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
                }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else {
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        let renamed = temporary.withCString { temporaryName in
            name.withCString { destinationName in
                renameat(directory, temporaryName, directory, destinationName)
            }
        }
        guard renamed == 0 else {
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
        completed = true
    }

    static func remove(named name: String, in directory: Int32) throws {
        let status = name.withCString { unlinkat(directory, $0, 0) }
        guard status == 0 || errno == ENOENT else {
            throw RemoteCommandResultExchangeError.unsafeFilesystemEntry
        }
    }
}
