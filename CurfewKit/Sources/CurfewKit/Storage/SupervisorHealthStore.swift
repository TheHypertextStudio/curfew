import Foundation

/// Local diagnostics contain no schedule policy or remote protocol state.
public nonisolated struct SupervisorHealthRecord: Codable, Equatable, Sendable {
    public let lastCheckedAt: Date
    public let launchFailure: String?

    public init(lastCheckedAt: Date, launchFailure: String? = nil) {
        self.lastCheckedAt = lastCheckedAt
        self.launchFailure = launchFailure
    }

    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(lastCheckedAt)
        return age >= -5 && age < 90
    }
}

/// App and supervisor share this atomic file within their flavor's local storage.
public final nonisolated class SupervisorHealthStore {
    public let recordURL: URL?
    private var memoryRecord: SupervisorHealthRecord?

    public init(recordURL: URL? = nil) {
        self.recordURL = recordURL
    }

    public static func production() -> SupervisorHealthStore {
        SupervisorHealthStore(
            recordURL: SharedPaths.applicationSupport
                .appendingPathComponent("supervisor-health.json")
        )
    }

    public func load() throws -> SupervisorHealthRecord? {
        guard let recordURL else { return memoryRecord }
        let data: Data
        do {
            data = try Data(contentsOf: recordURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        let record = try JSONDecoder().decode(SupervisorHealthRecord.self, from: data)
        try validate(record)
        return record
    }

    public func save(_ record: SupervisorHealthRecord) throws {
        try validate(record)
        guard let recordURL else {
            memoryRecord = record
            return
        }
        try FileManager.default.createDirectory(
            at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: recordURL.path
        )
    }

    private func validate(_ record: SupervisorHealthRecord) throws {
        guard record.lastCheckedAt.timeIntervalSince1970.isFinite,
              (record.launchFailure?.utf8.count ?? 0) <= 4096
        else { throw CocoaError(.coderReadCorrupt) }
    }
}
