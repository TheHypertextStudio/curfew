import Foundation

/// One of the four weekly allowance values a person sets in Settings →
/// Warnings and limits: how many extensions ("more time") and overrides they
/// get each week, and how long each one lasts.
public enum WeeklyLimit: String, Codable, CaseIterable, Sendable {
    case extensionCount = "extension_count"
    case extensionMinutes = "extension_minutes"
    case overrideCount = "override_count"
    case overrideMinutes = "override_minutes"
}

/// A raised weekly limit that has been requested but is not yet in force.
///
/// The limit-side twin of ``PendingScheduleChange``: a raise waits the same
/// cooldown a looser schedule waits
/// (``SchedulePolicyEngine/earliestEffectiveDate(for:requestedAt:)``
/// with ``ScheduleChangeClassification/weaker``), and until `effectiveAt`
/// passes every reader keeps using the value in ``CurfewSettings``. Lowering a
/// limit never produces one of these; it applies at once.
public struct PendingLimitChange: Codable, Equatable, Sendable {
    /// Which limit will change.
    public var limit: WeeklyLimit

    /// The value that replaces the one in force once `effectiveAt` passes.
    /// Always greater than the value in force while stored.
    public var value: Int

    /// When the raise was requested.
    public var requestedAt: Date

    /// The earliest moment the raise may apply.
    public var effectiveAt: Date

    public init(limit: WeeklyLimit, value: Int, requestedAt: Date, effectiveAt: Date) {
        self.limit = limit
        self.value = value
        self.requestedAt = requestedAt
        self.effectiveAt = effectiveAt
    }
}

public extension CurfewSettings {
    /// The value of `limit` in force now. Enforcement, the CLI, MCP and the
    /// widget read these stored fields directly, so a waiting raise is
    /// invisible to them by construction.
    subscript(limit: WeeklyLimit) -> Int {
        get {
            switch limit {
            case .extensionCount: extensionWeeklyLimit
            case .extensionMinutes: extensionDurationMinutes
            case .overrideCount: overrideWeeklyLimit
            case .overrideMinutes: overrideDurationMinutes
            }
        }
        set {
            switch limit {
            case .extensionCount: extensionWeeklyLimit = newValue
            case .extensionMinutes: extensionDurationMinutes = newValue
            case .overrideCount: overrideWeeklyLimit = newValue
            case .overrideMinutes: overrideDurationMinutes = newValue
            }
        }
    }

    /// The waiting raise for `limit`, if any.
    func pendingLimitChange(for limit: WeeklyLimit) -> PendingLimitChange? {
        pendingLimitChanges.first { $0.limit == limit }
    }

    /// What the person last asked for: the waiting raise when there is one,
    /// otherwise the value in force. Only Settings should read this.
    func requestedLimit(_ limit: WeeklyLimit) -> Int {
        pendingLimitChange(for: limit)?.value ?? self[limit]
    }
}
