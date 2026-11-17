import Foundation

// Sunrise is the morning half of Curfew: at unlock the Mac stays on the
// Sunrise screen until the person names what today is for. This file holds the
// pure parts: the words, the ordered steps the person can choose and reorder,
// the pages the gate shows, and the two facts read back from saved
// reflections (last night's note and today's one thing). Answers are saved as
// an ordinary morning reflection, so no stored or wire shape changes.

/// The lines Sunrise says. Kept in one place so views never write them inline.
public enum SunriseVoice {
    public static let greeting = "Morning."
    public static let question = "What is today for?"
    public static let startTheDay = "Start the day"
    public static let next = "Next"
    public static let skip = "Skip"
    public static let lastNightPrefix = "Last night you left:"
    public static let readiness = "How ready do you feel?"

    /// "Last night you left: (their words)".
    public static func lastNight(_ note: String) -> String {
        "\(lastNightPrefix) \(note)"
    }
}

/// What a Sunrise step shows.
public enum SunriseStepKind: Hashable, Sendable {
    /// Last night's "left for next time" answer. Shown, never answered.
    case lastNightNote
    /// "What is today for?", saved as the one thing.
    case oneThing
    /// How ready the person feels, a rating.
    case readiness
    /// One of the person's own morning questions, by its prompt identity.
    case question(UUID)
}

/// One step in the Sunrise gate: what it shows, whether it is on, and whether
/// it can be skipped. Last night's note is never required.
public struct SunriseStep: Hashable, Identifiable, Sendable {
    public var kind: SunriseStepKind
    public var isEnabled: Bool
    public var isRequired: Bool

    public var id: SunriseStepKind {
        kind
    }

    public init(kind: SunriseStepKind, isEnabled: Bool, isRequired: Bool) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.isRequired = kind == .lastNightNote ? false : isRequired
    }
}

extension SunriseStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, promptID, isEnabled, isRequired
    }

    private enum StoredKind: String, Codable {
        case lastNightNote, oneThing, readiness, question
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind: SunriseStepKind = switch try container.decode(StoredKind.self, forKey: .kind) {
        case .lastNightNote: .lastNightNote
        case .oneThing: .oneThing
        case .readiness: .readiness
        case .question: try .question(container.decode(UUID.self, forKey: .promptID))
        }
        try self.init(
            kind: kind,
            isEnabled: container.decode(Bool.self, forKey: .isEnabled),
            isRequired: container.decode(Bool.self, forKey: .isRequired)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch kind {
        case .lastNightNote: try container.encode(StoredKind.lastNightNote, forKey: .kind)
        case .oneThing: try container.encode(StoredKind.oneThing, forKey: .kind)
        case .readiness: try container.encode(StoredKind.readiness, forKey: .kind)
        case .question(let id):
            try container.encode(StoredKind.question, forKey: .kind)
            try container.encode(id, forKey: .promptID)
        }
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isRequired, forKey: .isRequired)
    }
}

/// The Shortcut a person picked to run after Sunrise.
public struct SunriseShortcut: Codable, Hashable, Sendable {
    /// The identifier `shortcuts list --show-identifiers` reports.
    public let identifier: String
    public let name: String

    public init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }
}

/// Sunrise choices local to this Mac. Never synchronized.
///
/// `steps == nil` means the person has never edited them; the steps are then
/// migrated from the morning prompts every time they are read, so prompts a
/// person had before Sunrise keep appearing in the same order.
public struct SunrisePreferences: Codable, Equatable, Sendable {
    public var steps: [SunriseStep]?
    public var shortcut: SunriseShortcut?

    public init(steps: [SunriseStep]? = nil, shortcut: SunriseShortcut? = nil) {
        self.steps = steps
        self.shortcut = shortcut
    }

    private enum CodingKeys: String, CodingKey {
        case steps, shortcut
    }

    /// An unreadable field falls back on its own, so a damaged step list
    /// migrates again instead of hiding the gate.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.steps = try? container.decodeIfPresent([SunriseStep].self, forKey: .steps)
        self.shortcut = try? container.decodeIfPresent(SunriseShortcut.self, forKey: .shortcut)
    }
}

/// Reads and writes ``SunrisePreferences`` in this Mac's defaults.
public final class SunrisePreferencesStore {
    public static let defaultsKey = "sunrise.preferences.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> SunrisePreferences {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let preferences = try? JSONDecoder().decode(SunrisePreferences.self, from: data)
        else { return SunrisePreferences() }
        return preferences
    }

    public func save(_ preferences: SunrisePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Resolves the ordered step list from what is stored and the current
/// morning prompts.
public enum SunriseSteps {
    /// - Without stored steps: last night's note, then the morning prompts in
    ///   their order (the one thing required, readiness and the person's own
    ///   questions skippable). The one thing is always present; readiness is
    ///   added switched off when its prompt had been removed.
    /// - With stored steps: their order and choices, minus questions whose
    ///   prompt is gone and duplicates, plus any prompt added elsewhere and any
    ///   missing built-in step at the end.
    public static func resolve(
        stored: [SunriseStep]?,
        morningPrompts: [ReflectionPrompt]
    ) -> [SunriseStep] {
        let questionIDs = morningPrompts.map(\.id).filter { !isBuiltIn($0) }
        guard let stored else {
            return migrated(from: morningPrompts)
        }
        var seen = Set<SunriseStepKind>()
        var steps: [SunriseStep] = []
        for step in stored where !seen.contains(step.kind) {
            if case .question(let id) = step.kind, !questionIDs.contains(id) {
                continue
            }
            seen.insert(step.kind)
            steps.append(SunriseStep(
                kind: step.kind, isEnabled: step.isEnabled, isRequired: step.isRequired
            ))
        }
        for kind in [SunriseStepKind.lastNightNote, .oneThing, .readiness]
            where !seen.contains(kind) {
            steps.append(defaultStep(kind))
            seen.insert(kind)
        }
        for id in questionIDs where !seen.contains(.question(id)) {
            steps.append(SunriseStep(kind: .question(id), isEnabled: true, isRequired: false))
        }
        return steps
    }

    private static func migrated(from prompts: [ReflectionPrompt]) -> [SunriseStep] {
        var steps = [defaultStep(.lastNightNote)]
        for prompt in prompts {
            switch prompt.id {
            case JournalPromptIDs.oneThing: steps.append(defaultStep(.oneThing))
            case JournalPromptIDs.readiness: steps.append(defaultStep(.readiness))
            default:
                steps.append(SunriseStep(
                    kind: .question(prompt.id), isEnabled: true, isRequired: false
                ))
            }
        }
        if !steps.contains(where: { $0.kind == .oneThing }) {
            steps.insert(defaultStep(.oneThing), at: 1)
        }
        if !steps.contains(where: { $0.kind == .readiness }) {
            steps.append(SunriseStep(kind: .readiness, isEnabled: false, isRequired: false))
        }
        return steps
    }

    private static func defaultStep(_ kind: SunriseStepKind) -> SunriseStep {
        SunriseStep(kind: kind, isEnabled: true, isRequired: kind == .oneThing)
    }

    static func isBuiltIn(_ id: UUID) -> Bool {
        id == JournalPromptIDs.oneThing || id == JournalPromptIDs.readiness
    }
}

/// One page of the Sunrise gate: an optional note line above an optional
/// question. A page with neither is never produced.
public struct SunriseGatePage: Equatable, Sendable {
    public let note: String?
    public let prompt: ReflectionPrompt?
    public let isRequired: Bool

    public init(note: String?, prompt: ReflectionPrompt?, isRequired: Bool) {
        self.note = note
        self.prompt = prompt
        self.isRequired = isRequired
    }

    /// A required question needs an answer; any non-empty text counts, so the
    /// person can always get through. Skippable pages always advance.
    public func canAdvance(with value: ReflectionValue?) -> Bool {
        guard isRequired, prompt != nil else { return true }
        switch value {
        case .text(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .rating, .mood: return true
        case nil: return false
        }
    }
}

/// Builds the gate's pages from the enabled steps.
public enum SunriseGate {
    /// The one thing's prompt. Its identity is what the Journal and Today read.
    public static var oneThingPrompt: ReflectionPrompt {
        ReflectionPrompt(id: JournalPromptIDs.oneThing, text: SunriseVoice.question, kind: .text)
    }

    /// Last night's note rides on the page of the next question; a note with
    /// nothing after it gets a page of its own. An empty note is left out.
    public static func pages(
        steps: [SunriseStep],
        morningPrompts: [ReflectionPrompt],
        lastNightNote: String?
    ) -> [SunriseGatePage] {
        let note = lastNightNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        var pendingNote: String?
        var pages: [SunriseGatePage] = []
        for step in steps where step.isEnabled {
            let prompt: ReflectionPrompt? = switch step.kind {
            case .lastNightNote: nil
            case .oneThing: oneThingPrompt
            case .readiness: morningPrompts.first { $0.id == JournalPromptIDs.readiness }
                ?? ReflectionDefaults.morningPrompts[1]
            case .question(let id): morningPrompts.first { $0.id == id }
            }
            if step.kind == .lastNightNote {
                if let note, !note.isEmpty {
                    pendingNote = note
                }
                continue
            }
            guard let prompt else { continue }
            pages.append(SunriseGatePage(
                note: pendingNote, prompt: prompt, isRequired: step.isRequired
            ))
            pendingNote = nil
        }
        if let pendingNote {
            pages.append(SunriseGatePage(note: pendingNote, prompt: nil, isRequired: false))
        }
        return pages
    }
}

/// Last night's "left for next time" answer.
public enum SunriseNote {
    /// How far back a note still greets the morning: Friday's note reaches
    /// Monday, last week's does not.
    public static let maximumAge: TimeInterval = 4 * 24 * 60 * 60

    public static func lastNight(in reflections: [Reflection], now: Date) -> String? {
        let candidates = reflections
            .filter {
                $0.gate == .evening && $0.timestamp <= now
                    && now.timeIntervalSince($0.timestamp) <= maximumAge
            }
            .sorted { $0.timestamp > $1.timestamp }
        for reflection in candidates {
            for answer in reflection.answers
                where answer.promptID == ReflectionDefaults.leftForNextTimePromptID {
                if case .text(let text) = answer.value {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            }
        }
        return nil
    }
}

/// Today's Sunrise, read from saved morning reflections.
public enum SunriseDay {
    private static func todaysMornings(
        in reflections: [Reflection], now: Date, calendar: Calendar
    ) -> [Reflection] {
        reflections
            .filter { $0.gate == .morning && calendar.isDate($0.timestamp, inSameDayAs: now) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Whether Sunrise was completed today.
    public static func isComplete(
        in reflections: [Reflection], now: Date, calendar: Calendar
    ) -> Bool {
        !todaysMornings(in: reflections, now: now, calendar: calendar).isEmpty
    }

    /// Today's one thing, trimmed; `nil` when none was named.
    public static func oneThing(
        in reflections: [Reflection], now: Date, calendar: Calendar
    ) -> String? {
        for reflection in todaysMornings(in: reflections, now: now, calendar: calendar).reversed() {
            for answer in reflection.answers where answer.promptID == JournalPromptIDs.oneThing {
                if case .text(let text) = answer.value {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }
        return nil
    }
}
