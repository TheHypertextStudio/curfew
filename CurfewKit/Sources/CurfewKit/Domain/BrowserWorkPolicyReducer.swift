import Foundation

public nonisolated struct BrowserSessionGrant: Codable, Equatable, Sendable {
    public let scope: BrowserDestinationScope
    public let expiresAt: Date
}

public nonisolated struct BrowserVisibleTask: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
}

public nonisolated struct BrowserRetainedSessionIdentity: Codable, Equatable, Sendable {
    public nonisolated enum ValidationError: Error, Equatable {
        case invalidIdentifier
    }

    public let sessionID: UUID
    public let organizationID: String
    public let taskID: String

    public static func validated(
        sessionID: UUID,
        organizationID: String,
        taskID: String
    ) throws -> Self {
        guard isValidIdentifier(organizationID), isValidIdentifier(taskID) else {
            throw ValidationError.invalidIdentifier
        }
        return Self(sessionID: sessionID, organizationID: organizationID, taskID: taskID)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try Self.validated(
            sessionID: container.decode(UUID.self, forKey: .sessionID),
            organizationID: container.decode(String.self, forKey: .organizationID),
            taskID: container.decode(String.self, forKey: .taskID)
        )
    }

    private init(sessionID: UUID, organizationID: String, taskID: String) {
        self.sessionID = sessionID
        self.organizationID = organizationID
        self.taskID = taskID
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        guard (1 ... 256).contains(value.utf8.count) else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || CharacterSet(charactersIn: "-_.")
                .contains($0)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID, organizationID, taskID
    }
}

public nonisolated struct BrowserPolicySnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let sessionID: UUID
    public let task: BrowserVisibleTask
    public let tracking: DocketTrackingState
    public let scopes: Set<BrowserDestinationScope>
    public let grants: [BrowserSessionGrant]
    public let breakEndsAt: Date?
    public let connectionIsHealthy: Bool
    public let generatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, sessionID, task, tracking, scopes, grants, breakEndsAt
        case connectionIsHealthy, generatedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(task, forKey: .task)
        try container.encode(tracking, forKey: .tracking)
        try container.encode(scopes, forKey: .scopes)
        try container.encode(grants, forKey: .grants)
        if let breakEndsAt {
            try container.encode(breakEndsAt, forKey: .breakEndsAt)
        } else {
            try container.encodeNil(forKey: .breakEndsAt)
        }
        try container.encode(connectionIsHealthy, forKey: .connectionIsHealthy)
        try container.encode(generatedAt, forKey: .generatedAt)
    }

    public func allows(_ destination: NormalizedHTTPDestination, at date: Date) -> Bool {
        if let breakEndsAt, breakEndsAt > date {
            return true
        }
        if scopes.contains(where: { $0.allows(destination) }) {
            return true
        }
        return grants.contains { $0.expiresAt > date && $0.scope.allows(destination) }
    }
}

public nonisolated struct BrowserWorkSessionReducer: Sendable {
    private nonisolated struct Session: Sendable {
        let id: UUID
        var task: DocketActiveWorkTask
        var tracking: DocketTrackingState
        var grants: [BrowserSessionGrant]
        var cooldowns: [NormalizedHTTPDestination: Date]
        var breakEndsAt: Date?
        var breakConsumed: Bool
    }

    private let docketScope: BrowserDestinationScope
    private var mappings: [WorkDestinationMapping]
    private var session: Session?
    private var lastDocketObservation: Date?
    private var docketIsHealthy = false

    public init(docketWebOrigin: URL, mappings: [WorkDestinationMapping]) {
        guard let normalized = try? NormalizedHTTPDestination(docketWebOrigin.absoluteString) else {
            preconditionFailure("The configured Docket web origin must use HTTP or HTTPS")
        }
        guard let docketScope = try? BrowserDestinationScope.validatedOrigin(normalized.origin)
        else {
            preconditionFailure("The configured Docket web origin must be an exact origin")
        }
        self.docketScope = docketScope
        self.mappings = mappings
    }

    public mutating func replaceMappings(_ mappings: [WorkDestinationMapping]) {
        self.mappings = mappings
    }

    public mutating func observe(_ work: DocketActiveWork, receivedAt _: Date) {
        guard work.schemaVersion == "active-work/1" else { return }
        if let lastDocketObservation, work.observedAt < lastDocketObservation {
            return
        }
        lastDocketObservation = work.observedAt
        docketIsHealthy = true

        guard let task = work.task else {
            if work.tracking == .idle {
                updateTracking(.idle)
            }
            return
        }
        if task.isTerminal {
            session = nil
            return
        }

        if session?.task.id == task.id {
            session?.task = task
            updateTracking(work.tracking)
            return
        }
        session = Session(
            id: UUID(),
            task: task,
            tracking: work.tracking,
            grants: [],
            cooldowns: [:],
            breakEndsAt: nil,
            breakConsumed: false
        )
    }

    public mutating func observeTaskState(
        sessionID: UUID,
        taskID: String,
        stateType: String,
        archivedAt: Date? = nil
    ) {
        guard session?.id == sessionID, session?.task.id == taskID else { return }
        docketIsHealthy = true
        if archivedAt != nil || DocketActiveWorkTask.isTerminal(stateType) {
            session = nil
        }
    }

    public mutating func markDocketUnavailable(at _: Date) {
        docketIsHealthy = false
    }

    public var canBeginBreak: Bool {
        guard let tracking = session?.tracking else { return false }
        return (tracking == .paused || tracking == .idle) && session?.breakConsumed == false
    }

    public mutating func beginBreak(at date: Date) -> Bool {
        guard canBeginBreak else { return false }
        session?.breakEndsAt = date.addingTimeInterval(15 * 60)
        session?.breakConsumed = true
        return true
    }

    @discardableResult
    public mutating func grant(
        _ scope: BrowserDestinationScope,
        for destination: NormalizedHTTPDestination,
        at date: Date
    ) -> Bool {
        guard session != nil, scope.allows(destination) else { return false }
        session?.grants.append(.init(
            scope: scope,
            expiresAt: date.addingTimeInterval(30 * 60)
        ))
        session?.cooldowns[destination] = nil
        return true
    }

    public mutating func deny(_ destination: NormalizedHTTPDestination, at date: Date) {
        guard session != nil else { return }
        session?.cooldowns[destination] = date.addingTimeInterval(5 * 60)
    }

    public func canReview(_ destination: NormalizedHTTPDestination, at date: Date) -> Bool {
        guard session != nil else { return false }
        guard let expiresAt = session?.cooldowns[destination] else { return true }
        return expiresAt <= date
    }

    func currentTask() -> DocketActiveWorkTask? {
        session?.task
    }

    func currentSessionID() -> UUID? {
        session?.id
    }

    public func policy(at date: Date) -> BrowserPolicySnapshot? {
        guard let session else { return nil }
        var scopes: Set<BrowserDestinationScope> = [docketScope]
        scopes.formUnion(mappings.lazy.filter { $0.matches(session.task) }.map(\.scope))
        scopes.formUnion(session.task.references.compactMap(Self.scope(for:)))
        return BrowserPolicySnapshot(
            schemaVersion: "browser-policy/1",
            sessionID: session.id,
            task: BrowserVisibleTask(id: session.task.id, title: session.task.title),
            tracking: session.tracking,
            scopes: scopes,
            grants: session.grants.filter { $0.expiresAt > date },
            breakEndsAt: session.breakEndsAt,
            connectionIsHealthy: docketIsHealthy,
            generatedAt: date
        )
    }

    private static func scope(
        for reference: DocketActiveWorkTask.Reference
    ) -> BrowserDestinationScope? {
        guard let destination = try? NormalizedHTTPDestination(reference.url) else { return nil }
        if destination.path == "/" {
            return try? BrowserDestinationScope.validatedOrigin(destination.origin)
        }
        return try? BrowserDestinationScope.validatedPathPrefix(
            origin: destination.origin,
            path: destination.path
        )
    }

    private mutating func updateTracking(_ tracking: DocketTrackingState) {
        guard let previous = session?.tracking else { return }
        session?.tracking = tracking
        if tracking == .running {
            session?.breakEndsAt = nil
            session?.breakConsumed = false
        } else if tracking != previous {
            session?.breakConsumed = false
        }
    }
}
