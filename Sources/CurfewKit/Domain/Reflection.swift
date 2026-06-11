import Foundation

/// The two reflection gates that bracket a working day in the Curfew Flow.
///
/// `morning` is the sunrise intent gate (raised on the day's first session);
/// `evening` is the sundown retrospective gate (presented inside the lockout
/// screen). The raw strings are the stable wire format — they appear in the
/// SQLite `gate` column, MCP tool responses, and CSV exports, and they double
/// as the ``GateKind`` constants for the activity-log marker events. Never
/// rename a case without a migration plan.
public enum ReflectionGate: String, Equatable, Hashable, CaseIterable, Codable {
    /// Start-of-day intent gate (sunrise). Raised once per day at the first
    /// session after the unlock boundary.
    case morning

    /// End-of-day retrospective gate (sundown). Presented inside the lockout
    /// screen as the optional shutdown ritual.
    case evening
}

/// The answer type a ``ReflectionPrompt`` expects, which determines how the
/// UI renders an input control and how ``ReflectionValue`` is constructed.
///
/// Raw strings are the stable wire format (settings JSON, SQLite, MCP). Adding
/// a kind is additive; renaming an existing one needs a migration plan.
public enum ReflectionPromptKind: String, Equatable, Hashable, CaseIterable, Codable {
    /// Free-form prose. Backed by ``ReflectionValue/text(_:)``.
    case text

    /// A 1–5 numeric rating (e.g. "how did today go?"). Backed by
    /// ``ReflectionValue/rating(_:)``.
    case rating

    /// A five-point mood pick. Backed by ``ReflectionValue/mood(_:)``.
    case mood
}

/// A five-point mood scale, ordered from worst to best. The ordinal
/// ``score`` (1…5) lets the Journal chart mood on the same axis as a rating
/// without special-casing the two prompt kinds.
public enum ReflectionMood: String, Equatable, Hashable, CaseIterable, Codable {
    case rough
    case low
    case neutral
    case good
    case great

    /// 1…5 ordinal so mood and rating can share a trend axis. `rough` = 1,
    /// `great` = 5.
    public var score: Int {
        switch self {
        case .rough: 1
        case .low: 2
        case .neutral: 3
        case .good: 4
        case .great: 5
        }
    }
}

/// One configured question shown at a reflection gate.
///
/// Prompts live in ``ReflectionConfiguration`` (user-editable, with defaults)
/// and are snapshotted into each ``ReflectionAnswer`` at capture time so later
/// edits to the prompt set never orphan or misattribute historical answers.
public struct ReflectionPrompt: Identifiable, Equatable, Hashable, Codable {
    /// Stable identifier. Preserved across edits so reordering or rewording a
    /// prompt keeps its identity (and links saved answers back to it).
    public let id: UUID

    /// The question text shown to the user.
    public var text: String

    /// What kind of answer this prompt collects.
    public var kind: ReflectionPromptKind

    /// Top of the rating scale for a ``ReflectionPromptKind/rating`` prompt
    /// (the scale runs `1...ratingMax`). Only meaningful when `kind == .rating`;
    /// ignored otherwise. Defaults to 5.
    public var ratingMax: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case kind
        case ratingMax
    }

    /// Memberwise initialiser. `id` defaults to a fresh UUID and `ratingMax` to
    /// 5 so call sites that build prompts inline only specify the meaningful
    /// fields.
    public init(
        id: UUID = UUID(),
        text: String,
        kind: ReflectionPromptKind,
        ratingMax: Int = 5
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.ratingMax = ratingMax
    }

    /// Decoder that tolerates prompts persisted before `ratingMax` existed by
    /// defaulting the scale to 5 — keeps the one-way-safe upgrade path.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.text = try container.decode(String.self, forKey: .text)
        self.kind = try container.decode(ReflectionPromptKind.self, forKey: .kind)
        self.ratingMax = try container.decodeIfPresent(Int.self, forKey: .ratingMax) ?? 5
    }
}

/// The typed payload of a single answer.
///
/// A sum type rather than a struct of optionals: a prompt produces exactly one
/// of these shapes, so the model makes the "rating with no text" /
/// "text with no mood" states unrepresentable. Encoded as a small tagged
/// envelope (`{ "type": …, … }`) so the wire format stays self-describing.
public enum ReflectionValue: Equatable, Hashable, Codable {
    /// Free-form prose from a ``ReflectionPromptKind/text`` prompt.
    case text(String)

    /// A rating from a ``ReflectionPromptKind/rating`` prompt: `value` on a
    /// `1...scale` axis. The scale is carried with the value so a rating is
    /// self-describing (a "4" means nothing without its "/5"), and so per-prompt
    /// configurable scales survive export, display, and later prompt edits.
    case rating(value: Int, scale: Int)

    /// A mood pick from a ``ReflectionPromptKind/mood`` prompt.
    case mood(ReflectionMood)

    /// The ``ReflectionPromptKind`` this value satisfies. Lets consumers pair
    /// a value back to its prompt kind without switching at the call site.
    public var kind: ReflectionPromptKind {
        switch self {
        case .text: .text
        case .rating: .rating
        case .mood: .mood
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case rating
        case scale
        case mood
    }

    private enum Discriminant: String, Codable {
        case text
        case rating
        case mood
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Discriminant.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .rating:
            self = .rating(
                value: try container.decode(Int.self, forKey: .rating),
                scale: try container.decodeIfPresent(Int.self, forKey: .scale) ?? 5
            )
        case .mood:
            self = .mood(try container.decode(ReflectionMood.self, forKey: .mood))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Discriminant.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .rating(let value, let scale):
            try container.encode(Discriminant.rating, forKey: .type)
            try container.encode(value, forKey: .rating)
            try container.encode(scale, forKey: .scale)
        case .mood(let value):
            try container.encode(Discriminant.mood, forKey: .type)
            try container.encode(value, forKey: .mood)
        }
    }
}

/// One captured answer: the value plus enough prompt context to render it
/// standalone in the Journal, an MCP response, or a CSV export.
public struct ReflectionAnswer: Identifiable, Equatable, Hashable, Codable {
    /// Identifies which ``ReflectionPrompt`` this answers. Stays valid even if
    /// the prompt is later reworded or removed from the configuration.
    public let promptID: UUID

    /// The prompt text exactly as shown when the answer was given. Snapshotted
    /// so historical entries read correctly after the prompt set is edited.
    public let promptTextSnapshot: String

    /// The typed answer payload.
    public let value: ReflectionValue

    /// `ReflectionAnswer` is identified by the prompt it answers — one answer
    /// per prompt within a reflection.
    public var id: UUID { promptID }

    /// Memberwise initialiser.
    public init(promptID: UUID, promptTextSnapshot: String, value: ReflectionValue) {
        self.promptID = promptID
        self.promptTextSnapshot = promptTextSnapshot
        self.value = value
    }
}

/// A completed reflection at one gate, on one day.
///
/// The answer set is the unit of storage (`ReflectionStore` serialises
/// `answers` to JSON in a single row). A reflection only exists once the user
/// has submitted it; a skipped gate writes no `Reflection`.
public struct Reflection: Identifiable, Equatable, Hashable, Codable {
    /// Stable identifier; primary key in ``ReflectionStore``.
    public let id: UUID

    /// When the reflection was submitted. Used as the store's bucketing key
    /// (which day / week a reflection belongs to).
    public let timestamp: Date

    /// Which gate produced this reflection.
    public let gate: ReflectionGate

    /// The user's answers, in prompt order at capture time.
    public let answers: [ReflectionAnswer]

    /// Memberwise initialiser. `id` defaults to a fresh UUID so typical call
    /// sites only specify the semantically-meaningful fields.
    public init(
        id: UUID = UUID(),
        timestamp: Date,
        gate: ReflectionGate,
        answers: [ReflectionAnswer]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.gate = gate
        self.answers = answers
    }
}

/// Serialises one ``ReflectionAnswer`` to a self-describing JSON object —
/// `{ "prompt": …, "type": "text"|"rating"|"mood", "value": … }` — shared by
/// the `curfew-mcp` `get_reflections` tool and the `curfew-ctl reflections`
/// command so both surfaces emit the identical shape.
public func reflectionAnswerJSON(_ answer: ReflectionAnswer) -> [String: Any] {
    var object: [String: Any] = ["prompt": answer.promptTextSnapshot]
    switch answer.value {
    case .text(let string):
        object["type"] = "text"
        object["value"] = string
    case .rating(let value, let scale):
        object["type"] = "rating"
        object["value"] = value
        object["max"] = scale
    case .mood(let mood):
        object["type"] = "mood"
        object["value"] = mood.rawValue
    }
    return object
}

/// Human-facing one-line rendering of a ``ReflectionValue`` — `"4/5"` for a
/// rating, the mood label for a mood, the prose for text. Shared by the Journal,
/// the Markdown export, and the CLI so they read consistently.
public func reflectionValueText(_ value: ReflectionValue) -> String {
    switch value {
    case .text(let string): string
    case .rating(let rating, let scale): "\(rating)/\(scale)"
    case .mood(let mood): mood.rawValue.capitalized
    }
}

/// Factory for the default prompt sets seeded into a fresh
/// ``ReflectionConfiguration``. Kept as stable data (fixed prompt UUIDs) so a
/// reinstall, or a config reset, reproduces the same prompt identities — and
/// so tests can reference a known prompt by id.
public enum ReflectionDefaults {
    /// Default sunrise intent prompts: one focus question and a neutral 1–5
    /// readiness rating. (Mood remains a selectable type, just not a default —
    /// the defaults stay neutral and rating-centric.)
    public static var morningPrompts: [ReflectionPrompt] {
        [
            ReflectionPrompt(
                id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!,
                text: "What's the one thing that matters most today?",
                kind: .text
            ),
            ReflectionPrompt(
                id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
                text: "How set up for the day do you feel?",
                kind: .rating
            )
        ]
    }

    /// Default sundown retrospective prompts: what got done, what's carried
    /// forward, and a 1–5 read on the day.
    public static var eveningPrompts: [ReflectionPrompt] {
        [
            ReflectionPrompt(
                id: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!,
                text: "What did you actually get done today?",
                kind: .text
            ),
            ReflectionPrompt(
                id: UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!,
                text: "What's unfinished or on your mind for tomorrow?",
                kind: .text
            ),
            ReflectionPrompt(
                id: UUID(uuidString: "B0000000-0000-0000-0000-000000000003")!,
                text: "How did today go?",
                kind: .rating
            )
        ]
    }

    /// Returns the default prompt set for `gate`.
    public static func prompts(for gate: ReflectionGate) -> [ReflectionPrompt] {
        switch gate {
        case .morning: morningPrompts
        case .evening: eveningPrompts
        }
    }
}

/// Pure serialisers that turn a list of ``Reflection`` into an exportable
/// document. Kept in CurfewKit (no UI/Foundation-UI dependency) so the app's
/// export menu, and any future CLI export, share one implementation and so the
/// formats are unit-testable.
public enum ReflectionExport {
    /// A human-readable Markdown journal: an `# Reflections` title, one `##`
    /// section per day (ascending), and `### Morning / ### Evening` blocks whose
    /// answers render as `**prompt**` with the value beneath (text) or inline
    /// (rating `n/max`, mood label). Empty input yields a title-only document so
    /// callers always get well-formed output.
    public static func markdown(
        _ reflections: [Reflection],
        calendar: Calendar = .current
    ) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        var lines = ["# Reflections", ""]
        let sorted = reflections.sorted { $0.timestamp < $1.timestamp }
        let byDay = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.timestamp) }

        for day in byDay.keys.sorted() {
            lines.append("## \(dayFormatter.string(from: day))")
            lines.append("")
            for reflection in byDay[day] ?? [] {
                let gateName = reflection.gate == .morning ? "Morning" : "Evening"
                lines.append("### \(gateName) · \(timeFormatter.string(from: reflection.timestamp))")
                for answer in reflection.answers {
                    switch answer.value {
                    case .text(let prose):
                        lines.append("- **\(answer.promptTextSnapshot)**")
                        lines.append("  \(prose)")
                    default:
                        lines.append(
                            "- **\(answer.promptTextSnapshot)** "
                                + reflectionValueText(answer.value)
                        )
                    }
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Structured JSON matching the `curfew.get_reflections` MCP shape:
    /// `{ "reflections": [ { timestamp, gate, answers: [...] } ] }`. Pretty-
    /// printed and sorted-key for stable diffs. Reuses ``reflectionAnswerJSON``.
    public static func json(_ reflections: [Reflection]) -> String {
        let iso = ISO8601DateFormatter()
        let items: [[String: Any]] = reflections
            .sorted { $0.timestamp < $1.timestamp }
            .map { reflection in
                [
                    "timestamp": iso.string(from: reflection.timestamp),
                    "gate": reflection.gate.rawValue,
                    "answers": reflection.answers.map(reflectionAnswerJSON)
                ]
            }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: ["reflections": items],
                options: [.prettyPrinted, .sortedKeys]
            ),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{\"reflections\":[]}"
        }
        return text
    }
}
