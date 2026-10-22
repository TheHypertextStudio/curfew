import Foundation

/// Temporary TDD scaffold for the shared presentation contract.
/// This value contains no restriction authority; no app consumer uses it yet.
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

    public struct Frame: Equatable, Sendable {
        public enum Phase: Equatable, Sendable {
            case allDay, night, sunrise, morning
        }

        public let phase: Phase
        public let sunriseProgress: Double
    }

    /// Deliberately neutral until the temporal tests establish behavioral RED.
    public func resolve(at _: Date, timeZone _: TimeZone) -> Frame {
        Frame(phase: .allDay, sunriseProgress: 0)
    }
}
