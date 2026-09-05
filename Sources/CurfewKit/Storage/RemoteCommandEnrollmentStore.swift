import Foundation

/// Public account binding used by the privileged verifier. No OAuth token or
/// private device key crosses into the daemon.
public struct RemoteCommandEnrollment: Codable, Equatable, Sendable {
    public let userID: String
    public let deviceID: UUID

    public init(userID: String, deviceID: UUID) {
        self.userID = userID
        self.deviceID = deviceID
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
        guard FileManager.default.fileExists(atPath: recordURL.path) else { return nil }
        return try JSONDecoder().decode(
            RemoteCommandEnrollment.self,
            from: Data(contentsOf: recordURL)
        )
    }
}
