import Foundation

public nonisolated enum BrowserNativeError: Error, Equatable {
    case messageTooLarge
    case invalidRequest
    case unauthorizedCaller
    case invalidIdentity
    case unsafeFile
    case invalidSignature
    case queueFull
}

public nonisolated enum BrowserNativeJSON {
    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

public nonisolated enum BrowserNativeFraming {
    public static let maximumInboundBytes = 64 * 1024 * 1024
    public static let maximumOutboundBytes = 1024 * 1024

    public static func take(from buffer: inout Data) throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self)) }
        guard length <= maximumInboundBytes else { throw BrowserNativeError.messageTooLarge }
        guard buffer.count >= length + 4 else { return nil }
        let result = Data(buffer.dropFirst(4).prefix(length))
        buffer.removeFirst(length + 4)
        return result
    }

    public static func encode(_ data: Data) throws -> Data {
        guard data.count <= maximumOutboundBytes else { throw BrowserNativeError.messageTooLarge }
        var length = UInt32(data.count)
        return withUnsafeBytes(of: &length) { Data($0) } + data
    }
}

public nonisolated struct BrowserNativeRequest: Codable, Equatable, Sendable {
    public nonisolated enum MessageType: String, Codable, Sendable {
        case getPolicy = "get_policy"
        case reviewDestination = "review_destination"
        case heartbeat
    }

    public let schemaVersion: String
    public let requestID: String
    public let type: MessageType
    public let sessionID: UUID?
    public let destination: NormalizedHTTPDestination?
    public var justification: String?
    public var challengeAnswer: String?

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= BrowserNativeFraming.maximumInboundBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeValue = object["type"] as? String,
              let type = MessageType(rawValue: typeValue)
        else { throw BrowserNativeError.invalidRequest }
        var keys: Set = ["schemaVersion", "requestId", "type"]
        if type == .reviewDestination {
            keys.formUnion(["sessionId", "destination", "justification", "challengeAnswer"])
            guard let destination = object["destination"] as? [String: Any],
                  Set(destination.keys) == ["origin", "path"],
                  let origin = destination["origin"] as? String,
                  let path = destination["path"] as? String
            else { throw BrowserNativeError.invalidRequest }
            _ = try BrowserDestinationScope.validatedOrigin(origin)
            _ = try BrowserDestinationScope.validatedPathPrefix(origin: origin, path: path)
        }
        guard Set(object.keys).isSubset(of: keys) else { throw BrowserNativeError.invalidRequest }
        let result = try BrowserNativeJSON.decode(Self.self, from: data)
        guard result.schemaVersion == "browser-host/1",
              !result.requestID.isEmpty, result.requestID.utf8.count <= 128
        else { throw BrowserNativeError.invalidRequest }
        if type == .reviewDestination {
            guard result.sessionID != nil, result.destination != nil,
                  let justification = result.justification,
                  !justification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  justification.utf8.count <= 8192,
                  (result.challengeAnswer?.utf8.count ?? 0) <= 8192
            else { throw BrowserNativeError.invalidRequest }
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, type, destination, justification, challengeAnswer
        case requestID = "requestId"
        case sessionID = "sessionId"
    }
}

public nonisolated struct BrowserNativeReviewResult: Codable, Equatable, Sendable {
    public let decision: String
    public let reason: String
    public let scope: BrowserDestinationScope?
    public let question: String?

    public init(
        decision: String,
        reason: String,
        scope: BrowserDestinationScope? = nil,
        question: String? = nil
    ) {
        self.decision = decision
        self.reason = reason
        self.scope = scope
        self.question = question
    }
}

public nonisolated struct BrowserNativeResponse: Codable, Sendable {
    public let schemaVersion = "browser-host/1"
    public let requestID: String
    public let type: BrowserNativeRequest.MessageType
    public var policy: BrowserPolicySnapshot?
    public var result: BrowserNativeReviewResult?
    public var error: String?
    public var generatedAt: Date

    public init(requestID: String, type: BrowserNativeRequest.MessageType, at date: Date = Date()) {
        self.requestID = requestID
        self.type = type
        self.generatedAt = date
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, type, policy, result, error, generatedAt
        case requestID = "requestId"
    }
}
