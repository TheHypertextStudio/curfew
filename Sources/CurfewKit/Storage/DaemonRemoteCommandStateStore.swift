import Foundation

public enum RemoteCommandResultStage: String, Codable, Equatable, Sendable {
    case applied
    case rejected
    case expired
}

public enum RemoteCommandRejectionCode: String, Codable, Equatable, Sendable {
    case ineligible
    case staleStatus = "stale_status"
    case outOfOrder = "out_of_order"
    case invalidSignature = "invalid_signature"
    case invalidDeadline = "invalid_deadline"
    case deviceUnavailable = "device_unavailable"
}

public struct RemoteCommandResult: Codable, Equatable, Sendable {
    public let commandID: UUID
    public let deviceID: UUID
    public let sequence: Int64
    public let stage: RemoteCommandResultStage
    public let resolvedAt: Date
    public let appliedDeadline: Date?
    public let rejectionCode: RemoteCommandRejectionCode?

    public init(
        commandID: UUID,
        deviceID: UUID,
        sequence: Int64,
        stage: RemoteCommandResultStage,
        resolvedAt: Date,
        appliedDeadline: Date? = nil,
        rejectionCode: RemoteCommandRejectionCode? = nil
    ) {
        self.commandID = commandID
        self.deviceID = deviceID
        self.sequence = sequence
        self.stage = stage
        self.resolvedAt = resolvedAt
        self.appliedDeadline = appliedDeadline
        self.rejectionCode = rejectionCode
    }

    private enum CodingKeys: String, CodingKey {
        case commandID = "commandId"
        case deviceID = "deviceId"
        case sequence
        case stage
        case resolvedAt
        case appliedDeadline
        case rejectionCode
    }
}

public struct DaemonRemoteCommandState: Codable, Equatable, Sendable {
    public var enrolledUserID: String?
    public var enrolledDeviceID: UUID?
    public var highestSequence: Int64
    public var activeLockout: LockoutDeadlineRecord?
    public var pendingResults: [RemoteCommandResult]
    public var resultsByIdempotencyKey: [String: RemoteCommandResult]

    public init(
        enrolledUserID: String? = nil,
        enrolledDeviceID: UUID? = nil,
        highestSequence: Int64 = 0,
        activeLockout: LockoutDeadlineRecord? = nil,
        pendingResults: [RemoteCommandResult] = [],
        resultsByIdempotencyKey: [String: RemoteCommandResult] = [:]
    ) {
        self.enrolledUserID = enrolledUserID
        self.enrolledDeviceID = enrolledDeviceID
        self.highestSequence = highestSequence
        self.activeLockout = activeLockout
        self.pendingResults = pendingResults
        self.resultsByIdempotencyKey = resultsByIdempotencyKey
    }
}

/// Root-owned, atomic state for replay protection, enforcement, and result delivery.
public struct DaemonRemoteCommandStateStore: Sendable {
    public let stateURL: URL

    public init(stateURL: URL) {
        self.stateURL = stateURL
    }

    public func load() throws -> DaemonRemoteCommandState {
        guard let data = try BoundedRegularFileReader.read(
            stateURL,
            maximumBytes: 1_048_576
        ) else {
            return DaemonRemoteCommandState()
        }
        return try Self.decoder.decode(DaemonRemoteCommandState.self, from: data)
    }

    public func save(_ state: DaemonRemoteCommandState) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try Self.encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
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
