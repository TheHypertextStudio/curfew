import Foundation

public struct RemoteCommandEligibilitySnapshot: Codable, Equatable, Sendable {
    public let statusVersion: Int
    public let scheduleDigest: String

    public init(statusVersion: Int, scheduleDigest: String) {
        self.statusVersion = statusVersion
        self.scheduleDigest = scheduleDigest
    }
}

public enum RemoteCommandEnrollmentStoreError: Error, Equatable {
    case missingEnrollment
}

/// Public account binding used by the privileged verifier. No OAuth token or
/// private device key crosses into the daemon.
public struct RemoteCommandEnrollment: Codable, Equatable, Sendable {
    public let userID: String
    public let deviceID: UUID
    public let eligibility: RemoteCommandEligibilitySnapshot?

    public init(
        userID: String,
        deviceID: UUID,
        eligibility: RemoteCommandEligibilitySnapshot? = nil
    ) {
        self.userID = userID
        self.deviceID = deviceID
        self.eligibility = eligibility
    }
}

public struct RemoteCommandEnrollmentStore: Sendable {
    public let recordURL: URL

    public init(recordURL: URL) {
        self.recordURL = recordURL
    }

    public func save(_ enrollment: RemoteCommandEnrollment) throws {
        try FileManager.default.createDirectory(
            at: recordURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(enrollment).write(to: recordURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: recordURL.path
        )
    }

    public func load() throws -> RemoteCommandEnrollment? {
        guard let data = try BoundedRegularFileReader.read(
            recordURL,
            maximumBytes: 65536
        ) else { return nil }
        return try JSONDecoder().decode(
            RemoteCommandEnrollment.self,
            from: data
        )
    }

    /// Records the exact local status frame against which the daemon may
    /// evaluate a subsequently delivered, coordinator-signed command. Updating
    /// this before network publication is deliberately conservative: once the
    /// local schedule changes, a command based on the older schedule must not
    /// become applicable merely because the newer report is still in flight.
    public func recordEligibility(statusVersion: Int, scheduleDigest: String) throws {
        guard let enrollment = try load() else {
            throw RemoteCommandEnrollmentStoreError.missingEnrollment
        }
        try save(RemoteCommandEnrollment(
            userID: enrollment.userID,
            deviceID: enrollment.deviceID,
            eligibility: RemoteCommandEligibilitySnapshot(
                statusVersion: statusVersion,
                scheduleDigest: scheduleDigest
            )
        ))
    }
}
