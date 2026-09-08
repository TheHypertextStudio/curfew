import CryptoKit
import Foundation

public nonisolated struct BrowserNativeEntry: Codable, Equatable, Sendable {
    public let id: UUID
    public var request: BrowserNativeRequest
    public let requestedAt: Date
    public var resolvedAt: Date?
    public var result: BrowserNativeReviewResult?

    public func isFresh(at date: Date) -> Bool {
        requestedAt <= date.addingTimeInterval(5) && date.timeIntervalSince(requestedAt) <= 60
    }
}

public nonisolated struct BrowserNativePolicyRecord: Codable, Equatable, Sendable {
    public let policy: BrowserPolicySnapshot?
    public let generatedAt: Date
}

public nonisolated struct BrowserNativeHealth: Codable, Sendable {
    public let extensionOrigin: String
    public let extensionSeenAt: Date
    public let hostSeenAt: Date
    public var isHealthy: Bool
}

private nonisolated struct BrowserSignedRecord: Codable {
    let payload: Data
    let signature: Data
}

private nonisolated struct BrowserNativeActivation: Codable {
    let installedAt: Date
}

/// The host and app use an HMAC-authenticated file queue under one UID, as
/// the MCP queue does. A lock prevents concurrent Chrome hosts losing entries.
public nonisolated struct BrowserNativeStore: Sendable {
    public static let maximumRecordBytes = 4 * 1024 * 1024
    public let directory: URL
    public var queueURL: URL {
        directory.appendingPathComponent("requests.json")
    }

    public var secretURL: URL {
        directory.appendingPathComponent(".secret")
    }

    public var policyURL: URL {
        directory.appendingPathComponent("policy.json")
    }

    public var heartbeatURL: URL {
        directory.appendingPathComponent("heartbeat.json")
    }

    public var activeURL: URL {
        directory.appendingPathComponent("active.json")
    }

    public init(directory: URL = SharedPaths.applicationSupport.appendingPathComponent(
        "browser",
        isDirectory: true
    )) {
        self.directory = directory
    }

    public func activate() throws {
        try BrowserNativeFiles.locked(directory: directory) {
            _ = try key(create: true)
            try save(BrowserNativeActivation(installedAt: Date()), to: activeURL)
        }
    }

    public func isActive() throws -> Bool {
        try load(BrowserNativeActivation.self, from: activeURL) != nil
    }

    public func deactivate() throws {
        guard FileManager.default.fileExists(atPath: activeURL.path) else { return }
        try BrowserNativeFiles.locked(directory: directory, createDirectory: false) {
            if FileManager.default.fileExists(atPath: activeURL.path) {
                try FileManager.default.removeItem(at: activeURL)
            }
        }
    }

    private func whileActive<T>(_ operation: () throws -> T) throws -> T {
        // Only installation creates the directory and lock. A host that
        // outlives uninstall must never recreate either while checking access.
        try BrowserNativeFiles.locked(directory: directory, createDirectory: false) {
            guard try isActive() else { throw BrowserNativeError.inactiveInstallation }
            return try operation()
        }
    }

    public func enqueue(_ request: BrowserNativeRequest, at date: Date) throws -> UUID {
        try whileActive {
            _ = try BrowserNativeRequest.decode(BrowserNativeJSON.encode(request))
            var entries = try loadEntries()
            entries = pruned(entries, at: date)
            guard entries.count < 128 else { throw BrowserNativeError.queueFull }
            let entry = BrowserNativeEntry(id: UUID(), request: request, requestedAt: date)
            entries.append(entry)
            try save(entries, to: queueURL)
            return entry.id
        }
    }

    public func pending(at date: Date) throws -> [BrowserNativeEntry] {
        try loadEntries().filter { $0.result == nil && $0.isFresh(at: date) }
    }

    public func resolve(id: UUID, result: BrowserNativeReviewResult, at date: Date) throws {
        try whileActive {
            var entries = try loadEntries()
            guard let index = entries.firstIndex(where: { $0.id == id && $0.result == nil })
            else { return }
            entries[index].request.justification = nil
            entries[index].request.challengeAnswer = nil
            entries[index].result = result
            entries[index].resolvedAt = date
            try save(entries, to: queueURL)
        }
    }

    public func response(id: UUID) throws -> BrowserNativeEntry? {
        try loadEntries()
            .first {
                $0.id == id && $0.result != nil && $0.request.justification == nil && $0.request
                    .challengeAnswer == nil
            }
    }

    public func prune(at date: Date) throws {
        try whileActive {
            let entries = try loadEntries()
            let remaining = pruned(entries, at: date)
            if remaining != entries {
                try save(remaining, to: queueURL)
            }
        }
    }

    public func writePolicy(_ policy: BrowserPolicySnapshot?, at date: Date) throws {
        try whileActive {
            try save(BrowserNativePolicyRecord(policy: policy, generatedAt: date), to: policyURL)
        }
    }

    public func readPolicy() throws -> BrowserNativePolicyRecord? {
        try load(BrowserNativePolicyRecord.self, from: policyURL)
    }

    public func recordHeartbeat(origin: String, at date: Date) throws {
        try whileActive {
            try save(
                BrowserNativeHealth(
                    extensionOrigin: origin,
                    extensionSeenAt: date,
                    hostSeenAt: date,
                    isHealthy: true
                ),
                to: heartbeatURL
            )
        }
    }

    public func health(at date: Date) throws -> BrowserNativeHealth {
        guard var health = try load(BrowserNativeHealth.self, from: heartbeatURL) else {
            return BrowserNativeHealth(
                extensionOrigin: "",
                extensionSeenAt: .distantPast,
                hostSeenAt: .distantPast,
                isHealthy: false
            )
        }
        health.isHealthy = [health.extensionSeenAt, health.hostSeenAt].allSatisfy {
            $0 <= date.addingTimeInterval(5) && date.timeIntervalSince($0) <= 60
        }
        return health
    }

    private func pruned(_ entries: [BrowserNativeEntry], at date: Date) -> [BrowserNativeEntry] {
        entries.filter { entry in
            if let resolvedAt = entry.resolvedAt {
                return date.timeIntervalSince(resolvedAt) < 120
            }
            return entry.isFresh(at: date)
        }
    }

    private func loadEntries() throws -> [BrowserNativeEntry] {
        try load([BrowserNativeEntry].self, from: queueURL) ?? []
    }

    private func key(create: Bool) throws -> SymmetricKey {
        if let data = try BrowserNativeFiles.read(secretURL, maximumBytes: 32) {
            guard data.count == 32 else { throw BrowserNativeError.invalidSignature }
            return SymmetricKey(data: data)
        }
        guard create else { throw BrowserNativeError.invalidSignature }
        let key = SymmetricKey(size: .bits256)
        try BrowserNativeFiles.write(key.withUnsafeBytes { Data($0) }, to: secretURL)
        return key
    }

    private func save(_ value: some Encodable, to url: URL) throws {
        let payload = try BrowserNativeJSON.encode(value)
        let signature = try Data(HMAC<SHA256>.authenticationCode(
            for: payload,
            using: key(create: false)
        ))
        let record = try BrowserNativeJSON.encode(BrowserSignedRecord(
            payload: payload,
            signature: signature
        ))
        guard record.count <= Self.maximumRecordBytes
        else { throw BrowserNativeError.messageTooLarge }
        try BrowserNativeFiles.write(record, to: url)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard let data = try BrowserNativeFiles.read(url, maximumBytes: Self.maximumRecordBytes)
        else { return nil }
        let record = try BrowserNativeJSON.decode(BrowserSignedRecord.self, from: data)
        guard try HMAC<SHA256>.isValidAuthenticationCode(
            record.signature,
            authenticating: record.payload,
            using: key(create: false)
        ) else {
            throw BrowserNativeError.invalidSignature
        }
        return try BrowserNativeJSON.decode(type, from: record.payload)
    }
}
