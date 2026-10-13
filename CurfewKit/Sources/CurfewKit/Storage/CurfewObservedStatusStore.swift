import Darwin
import Foundation

/// Last enforcement state settled by the running app, not a schedule forecast.
/// Local readers must reject stale snapshots instead of claiming a live phase.
public struct CurfewObservedStatus: Codable, Equatable, Sendable {
    public let phase: String
    public let warningStage: String
    public let minutesRemaining: Int?
    public let canRequestExtension: Bool
    public let lockDate: Date?
    public let unlockDate: Date?
    public let trigger: String?
    public let mode: String?
    public let observedAt: Date
    public let unavailableReason: String?
    public let writerPID: Int32

    public var availabilityDescription: String {
        switch unavailableReason {
        case "curfew_off": "Curfew is off."
        case "another_curfew_enforces":
            "Another Curfew app is enforcing; this build is standing by."
        case "enforcement_degraded":
            "Curfew protection is degraded. Check Curfew Settings before relying on a lockout."
        default: "Curfew has not reported active enforcement recently."
        }
    }

    public init(
        evaluation: CurfewEvaluation,
        observedAt: Date,
        enforcementRunning: Bool,
        ownsLockout: Bool,
        protectionHealthy: Bool = true,
        mode: CurfewMode = .time,
        writerPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.observedAt = observedAt
        self.writerPID = writerPID
        guard enforcementRunning,
              evaluation.phase != .locked || ownsLockout,
              protectionHealthy
        else {
            self.phase = "unknown"
            self.warningStage = "none"
            self.minutesRemaining = nil
            self.canRequestExtension = false
            self.lockDate = nil
            self.unlockDate = nil
            self.trigger = nil
            self.mode = nil
            if !enforcementRunning {
                self.unavailableReason = "curfew_off"
            } else if !protectionHealthy {
                self.unavailableReason = "enforcement_degraded"
            } else if evaluation.phase == .locked, !ownsLockout {
                self.unavailableReason = "another_curfew_enforces"
            } else {
                self.unavailableReason = "enforcement_unavailable"
            }
            return
        }

        self.phase = phaseName(evaluation.phase)
        self.warningStage = Self.warningStageName(evaluation.warningStage)
        self.minutesRemaining = evaluation.phase == .dayOff ? nil : evaluation.minutesRemaining
        self.canRequestExtension = evaluation.canRequestExtension
        self.lockDate = evaluation.lockDate
        self.unlockDate = evaluation.unlockDate
        self.trigger = evaluation.trigger.rawValue
        self.mode = mode.rawValue
        self.unavailableReason = nil
    }

    private static func warningStageName(_ stage: WarningStage) -> String {
        switch stage {
        case .none: "none"
        case .thirtyMinutes: "T-30"
        case .fifteenMinutes: "T-15"
        case .fiveMinutes: "T-5"
        case .twoMinutes: "T-2"
        case .oneMinute: "T-1"
        case .lockout: "lockout"
        }
    }

    fileprivate func hasSameState(as other: Self) -> Bool {
        phase == other.phase &&
            warningStage == other.warningStage &&
            minutesRemaining == other.minutesRemaining &&
            canRequestExtension == other.canRequestExtension &&
            lockDate == other.lockDate &&
            unlockDate == other.unlockDate &&
            trigger == other.trigger &&
            mode == other.mode &&
            unavailableReason == other.unavailableReason
    }
}

/// Atomic, user-owned mirror for bundled CLI and local MCP read-only tools.
/// It is advisory: the root daemon remains the lockout authority.
public struct CurfewObservedStatusStore {
    public let fileURL: URL

    public init(fileURL: URL = SharedPaths.observedEnforcementStatus) {
        self.fileURL = fileURL
    }

    public func save(_ status: CurfewObservedStatus) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(status)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public func loadFresh(
        at now: Date,
        maximumAge: TimeInterval = 60,
        isWriterAlive: (Int32) -> Bool = CurfewObservedStatusStore.processIsAlive
    ) -> CurfewObservedStatus? {
        guard let data = try? BoundedRegularFileReader.read(fileURL, maximumBytes: 4096)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let status = try? decoder.decode(CurfewObservedStatus.self, from: data),
              status.writerPID > 0,
              isWriterAlive(status.writerPID),
              status.observedAt <= now,
              now.timeIntervalSince(status.observedAt) <= maximumAge
        else { return nil }
        return status
    }

    public static func processIsAlive(_ pid: Int32) -> Bool {
        pid > 0 && (Darwin.kill(pid, 0) == 0 || errno == EPERM)
    }

    /// Serialize the incumbent check and atomic replacement across app
    /// processes. A busy writer skips this tick instead of blocking the UI.
    public func withPublicationLock(_ body: () throws -> Void) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let descriptor = Darwin.open(
            fileURL.appendingPathExtension("lock").path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        guard Darwin.lockf(descriptor, F_TLOCK, 0) == 0 else {
            if errno == EACCES || errno == EAGAIN {
                return
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.lockf(descriptor, F_ULOCK, 0) }
        try body()
    }
}

/// Coalesces unchanged one-second app ticks while publishing state transitions
/// immediately and refreshing a stable observation before readers mark it stale.
public final class CurfewObservedStatusPublisher {
    private let store: CurfewObservedStatusStore
    private let refreshInterval: TimeInterval
    private let writerPID: Int32
    private let isWriterAlive: (Int32) -> Bool
    private var lastPublished: CurfewObservedStatus?

    public init(
        store: CurfewObservedStatusStore = CurfewObservedStatusStore(),
        refreshInterval: TimeInterval = 15,
        writerPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        isWriterAlive: @escaping (Int32) -> Bool = CurfewObservedStatusStore.processIsAlive
    ) {
        self.store = store
        self.refreshInterval = refreshInterval
        self.writerPID = writerPID
        self.isWriterAlive = isWriterAlive
    }

    public func publish(
        evaluation: CurfewEvaluation,
        observedAt: Date,
        enforcementRunning: Bool,
        ownsLockout: Bool,
        protectionHealthy: Bool = true,
        mode: CurfewMode = .time
    ) throws {
        let status = CurfewObservedStatus(
            evaluation: evaluation,
            observedAt: observedAt,
            enforcementRunning: enforcementRunning,
            ownsLockout: ownsLockout,
            protectionHealthy: protectionHealthy,
            mode: mode,
            writerPID: writerPID
        )
        try store.withPublicationLock {
            let incumbent = store.loadFresh(at: observedAt, isWriterAlive: isWriterAlive)
            if let lastPublished,
               status.hasSameState(as: lastPublished),
               incumbent?.writerPID == writerPID,
               observedAt >= lastPublished.observedAt,
               observedAt.timeIntervalSince(lastPublished.observedAt) < refreshInterval {
                return
            }
            if let incumbent, incumbent.writerPID != writerPID,
               Self.priority(of: incumbent) > Self.priority(of: status) ||
               Self.priority(of: incumbent) == Self.priority(of: status) &&
               incumbent.writerPID < writerPID {
                return
            }
            try store.save(status)
            lastPublished = status
        }
    }

    private static func priority(of status: CurfewObservedStatus) -> Int {
        switch status.phase {
        case "locked": 3
        case "unknown": 1
        default: 2
        }
    }
}
