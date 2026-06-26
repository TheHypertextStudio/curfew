import Foundation

/// User-editable configuration for the morning and evening reflection gates.
///
/// Persisted as its own `UserDefaults` blob via ``CurfewSettingsStore`` rather
/// than folded into ``CurfewSettings`` — reflection prompts are local-only and
/// evolve independently of the CloudKit-synced settings unit, so keeping them
/// separate avoids churn on the synced struct's custom coder.
///
/// Each gate carries an `enabled` flag (the feature's on/off control — there is
/// no separate `FeatureFlag`, since the per-gate toggles are the natural gate)
/// and its own ordered prompt set. A fresh install gets ``ReflectionDefaults``
/// for both gates with both enabled.
public struct ReflectionConfiguration: Equatable, Codable {
    /// Whether the sunrise intent gate is raised at the day's first session.
    public var morningEnabled: Bool

    /// Whether the sundown retrospective gate is offered inside the lockout.
    public var eveningEnabled: Bool

    /// Ordered prompts shown at the morning gate.
    public var morningPrompts: [ReflectionPrompt]

    /// Ordered prompts shown at the evening gate.
    public var eveningPrompts: [ReflectionPrompt]

    private enum CodingKeys: String, CodingKey {
        case morningEnabled
        case eveningEnabled
        case morningPrompts
        case eveningPrompts
    }

    /// Memberwise initialiser.
    public init(
        morningEnabled: Bool,
        eveningEnabled: Bool,
        morningPrompts: [ReflectionPrompt],
        eveningPrompts: [ReflectionPrompt]
    ) {
        self.morningEnabled = morningEnabled
        self.eveningEnabled = eveningEnabled
        self.morningPrompts = morningPrompts
        self.eveningPrompts = eveningPrompts
    }

    /// Decoder that tolerates a partially-written or older payload: every
    /// field falls back to its default so a malformed store still yields a
    /// usable configuration rather than throwing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.morningEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .morningEnabled
        ) ?? true
        self.eveningEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .eveningEnabled
        ) ?? true
        self.morningPrompts = try container.decodeIfPresent(
            [ReflectionPrompt].self,
            forKey: .morningPrompts
        ) ?? ReflectionDefaults.morningPrompts
        self.eveningPrompts = try container.decodeIfPresent(
            [ReflectionPrompt].self,
            forKey: .eveningPrompts
        ) ?? ReflectionDefaults.eveningPrompts
    }

    /// Returns the prompt set for `gate`.
    public func prompts(for gate: ReflectionGate) -> [ReflectionPrompt] {
        switch gate {
        case .morning: morningPrompts
        case .evening: eveningPrompts
        }
    }

    /// Whether `gate` is currently enabled.
    public func isEnabled(_ gate: ReflectionGate) -> Bool {
        switch gate {
        case .morning: morningEnabled
        case .evening: eveningEnabled
        }
    }

    /// Factory defaults for a fresh install: both gates on, seeded from
    /// ``ReflectionDefaults``.
    public static var `default`: ReflectionConfiguration {
        ReflectionConfiguration(
            morningEnabled: true,
            eveningEnabled: true,
            morningPrompts: ReflectionDefaults.morningPrompts,
            eveningPrompts: ReflectionDefaults.eveningPrompts
        )
    }
}
