import Foundation

/// Local grants and consumed budgets survive process loss independently of settings sync.
public struct EnforcementRuntimeState: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var dayToken: String
    public var extensionMinutes: Int
    public var snoozeMinutes: Int
    public var extensionUses: Int
    public var overrideUses: Int
    public var extensionResetBoundary: Date?
    public var overrideResetBoundary: Date?
    public var overrideUntil: Date?

    public init(
        dayToken: String,
        extensionMinutes: Int = 0,
        snoozeMinutes: Int = 0,
        extensionUses: Int = 0,
        overrideUses: Int = 0,
        extensionResetBoundary: Date? = nil,
        overrideResetBoundary: Date? = nil,
        overrideUntil: Date? = nil
    ) {
        self.dayToken = dayToken
        self.extensionMinutes = extensionMinutes
        self.snoozeMinutes = snoozeMinutes
        self.extensionUses = extensionUses
        self.overrideUses = overrideUses
        self.extensionResetBoundary = extensionResetBoundary
        self.overrideResetBoundary = overrideResetBoundary
        self.overrideUntil = overrideUntil
    }
}
