import Foundation

/// Immutable presentation context shared by the app and companion, without restriction authority.
public nonisolated struct RestSceneSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let expiresAt: Date
    public let appearance: RestAppearancePreferences
    public let lockDate: Date?
    public let unlockDate: Date?

    public init(
        version: Int,
        expiresAt: Date,
        appearance: RestAppearancePreferences,
        lockDate: Date?,
        unlockDate: Date?
    ) {
        self.version = version
        self.expiresAt = expiresAt
        self.appearance = appearance
        self.lockDate = lockDate
        self.unlockDate = unlockDate
    }

    public enum Phase: Equatable, Sendable {
        case allDay, night, sunrise, morning
    }

    public struct Frame: Equatable, Sendable {
        public let phase: Phase
        public let sunriseProgress: Double
    }

    /// Recomputes presentation from absolute timestamps, independently of local clock formatting.
    public func resolve(at now: Date, timeZone _: TimeZone) -> Frame {
        let neutral = Frame(phase: .allDay, sunriseProgress: 0)
        guard version == 1,
              now.timeIntervalSinceReferenceDate.isFinite,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              now < expiresAt,
              let lockDate,
              let unlockDate,
              lockDate.timeIntervalSinceReferenceDate.isFinite,
              unlockDate.timeIntervalSinceReferenceDate.isFinite,
              lockDate < unlockDate,
              now >= lockDate
        else { return neutral }

        if now >= unlockDate {
            return Frame(phase: .morning, sunriseProgress: 1)
        }

        let leadSeconds = Double(appearance.sunriseLeadMinutes) * 60
        let remaining = unlockDate.timeIntervalSince(now)
        guard remaining <= leadSeconds else {
            return Frame(phase: .night, sunriseProgress: 0)
        }
        return Frame(phase: .sunrise, sunriseProgress: min(1, max(0, 1 - remaining / leadSeconds)))
    }
}

public extension RestSceneSnapshot.Frame {
    typealias Phase = RestSceneSnapshot.Phase
}
