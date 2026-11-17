@testable import CurfewKit
import Foundation
import Testing

/// The ordered Sunrise steps: defaults, migration from the morning prompts a
/// person already had, reconciliation with later prompt edits, and the gate
/// pages built from them.
struct SunriseStepsTests {
    private let custom = ReflectionPrompt(
        id: UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!,
        text: "Who do I owe a reply?",
        kind: .text
    )

    @Test("A fresh install gets note, the one thing (required), then readiness (skippable)")
    func defaults() {
        let steps = SunriseSteps.resolve(
            stored: nil,
            morningPrompts: ReflectionDefaults.morningPrompts
        )
        #expect(steps.map(\.kind) == [.lastNightNote, .oneThing, .readiness])
        #expect(!steps.contains { !$0.isEnabled })
        #expect(steps.map(\.isRequired) == [false, true, false])
    }

    @Test("Existing custom morning prompts carry over as skippable steps in their order")
    func migratesCustomPrompts() {
        let prompts = [
            ReflectionDefaults.morningPrompts[0],
            custom,
            ReflectionDefaults.morningPrompts[1]
        ]
        let steps = SunriseSteps.resolve(stored: nil, morningPrompts: prompts)
        #expect(steps.map(\.kind) == [.lastNightNote, .oneThing, .question(custom.id), .readiness])
        #expect(steps[2].isEnabled)
        #expect(!steps[2].isRequired)
    }

    @Test("A removed readiness prompt migrates as a readiness step that is off")
    func migratesRemovedReadinessAsOff() {
        let steps = SunriseSteps.resolve(
            stored: nil, morningPrompts: [ReflectionDefaults.morningPrompts[0], custom]
        )
        let readiness = steps.first { $0.kind == .readiness }
        #expect(readiness?.isEnabled == false)
        #expect(steps.map(\.kind) == [.lastNightNote, .oneThing, .question(custom.id), .readiness])
    }

    @Test("The one thing always exists, even when its prompt had been removed")
    func oneThingAlwaysPresent() {
        let steps = SunriseSteps.resolve(stored: nil, morningPrompts: [custom])
        #expect(steps.contains { $0.kind == .oneThing && $0.isEnabled && $0.isRequired })
    }

    @Test("Stored steps keep their order and drop questions whose prompt is gone")
    func reconcilesStoredSteps() {
        let stored = [
            SunriseStep(kind: .readiness, isEnabled: true, isRequired: true),
            SunriseStep(kind: .question(custom.id), isEnabled: false, isRequired: false),
            SunriseStep(kind: .oneThing, isEnabled: true, isRequired: false),
            SunriseStep(kind: .lastNightNote, isEnabled: false, isRequired: false)
        ]
        let kept = SunriseSteps.resolve(stored: stored, morningPrompts: [custom])
        #expect(kept == stored)
        let pruned = SunriseSteps.resolve(stored: stored, morningPrompts: [])
        #expect(pruned.map(\.kind) == [.readiness, .oneThing, .lastNightNote])
    }

    @Test("A prompt added elsewhere joins the end as a skippable question")
    func appendsNewPrompts() {
        let stored = SunriseSteps.resolve(
            stored: nil,
            morningPrompts: ReflectionDefaults.morningPrompts
        )
        let steps = SunriseSteps.resolve(
            stored: stored, morningPrompts: ReflectionDefaults.morningPrompts + [custom]
        )
        #expect(steps.last == SunriseStep(
            kind: .question(custom.id),
            isEnabled: true,
            isRequired: false
        ))
    }

    @Test("Last night's note is never required, however it was stored")
    func noteNeverRequired() {
        let stored = [SunriseStep(kind: .lastNightNote, isEnabled: true, isRequired: true)]
        let steps = SunriseSteps.resolve(stored: stored, morningPrompts: [])
        #expect(steps.first { $0.kind == .lastNightNote }?.isRequired == false)
        #expect(steps.filter { $0.kind == .lastNightNote }.count == 1)
    }

    @Test("Duplicate stored steps collapse to the first")
    func duplicatesCollapse() {
        let stored = [
            SunriseStep(kind: .oneThing, isEnabled: true, isRequired: true),
            SunriseStep(kind: .oneThing, isEnabled: false, isRequired: false)
        ]
        let steps = SunriseSteps.resolve(stored: stored, morningPrompts: [])
        #expect(steps.filter { $0.kind == .oneThing } == [stored[0]])
    }

    @Test("Steps round-trip through their stored form")
    func codable() throws {
        let preferences = SunrisePreferences(
            steps: [
                SunriseStep(kind: .lastNightNote, isEnabled: true, isRequired: false),
                SunriseStep(kind: .question(custom.id), isEnabled: false, isRequired: true)
            ],
            shortcut: SunriseShortcut(identifier: "ABC", name: "Plan my day")
        )
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(SunrisePreferences.self, from: data) == preferences)
    }

    @Test("An unreadable stored step list falls back to migration")
    func corruptStorageFallsBack() throws {
        let data = Data(#"{"steps":[{"kind":"mystery"}]}"#.utf8)
        let decoded = try JSONDecoder().decode(SunrisePreferences.self, from: data)
        #expect(decoded.steps == nil)
    }

    @Test("The store saves and loads preferences locally")
    func store() throws {
        let suite = "SunriseStepsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SunrisePreferencesStore(defaults: defaults)
        #expect(store.load() == SunrisePreferences())
        let saved = SunrisePreferences(
            steps: nil,
            shortcut: SunriseShortcut(identifier: "X", name: "Y")
        )
        store.save(saved)
        #expect(store.load() == saved)
    }
}

/// The pages the gate shows, built from enabled steps.
struct SunriseGatePagesTests {
    private let custom = ReflectionPrompt(text: "Who do I owe a reply?", kind: .text)

    private var defaults: [SunriseStep] {
        SunriseSteps.resolve(stored: nil, morningPrompts: ReflectionDefaults.morningPrompts)
    }

    @Test("Last night's note rides on the first question, which is the one thing")
    func noteJoinsFollowingQuestion() {
        let pages = SunriseGate.pages(
            steps: defaults, morningPrompts: ReflectionDefaults.morningPrompts,
            lastNightNote: "pick up the billing migration"
        )
        #expect(pages.count == 2)
        #expect(pages[0].note == "pick up the billing migration")
        #expect(pages[0].prompt?.id == JournalPromptIDs.oneThing)
        #expect(pages[0].prompt?.text == SunriseVoice.question)
        #expect(pages[0].isRequired)
        #expect(pages[1].note == nil)
        #expect(pages[1].prompt?.id == JournalPromptIDs.readiness)
        #expect(!pages[1].isRequired)
    }

    @Test("Without a note there is no note line")
    func noNote() {
        let pages = SunriseGate.pages(
            steps: defaults, morningPrompts: ReflectionDefaults.morningPrompts, lastNightNote: "  "
        )
        #expect(pages.allSatisfy { $0.note == nil })
        #expect(pages.count == 2)
    }

    @Test("Steps that are off are left out; a trailing note gets its own page")
    func trailingNote() {
        let steps = [
            SunriseStep(kind: .oneThing, isEnabled: true, isRequired: true),
            SunriseStep(kind: .readiness, isEnabled: false, isRequired: false),
            SunriseStep(kind: .lastNightNote, isEnabled: true, isRequired: false)
        ]
        let pages = SunriseGate.pages(
            steps: steps, morningPrompts: ReflectionDefaults.morningPrompts, lastNightNote: "a"
        )
        #expect(pages.count == 2)
        #expect(pages[1].prompt == nil)
        #expect(pages[1].note == "a")
    }

    @Test("A custom question uses its own prompt")
    func customQuestion() {
        let steps = [SunriseStep(kind: .question(custom.id), isEnabled: true, isRequired: false)]
        let pages = SunriseGate.pages(steps: steps, morningPrompts: [custom], lastNightNote: nil)
        #expect(pages.map(\.prompt) == [custom])
    }

    @Test("A question with no words yet is left out of the gate")
    func blankQuestion() {
        let blank = ReflectionPrompt(text: "  ", kind: .text)
        let steps = [SunriseStep(kind: .question(blank.id), isEnabled: true, isRequired: true)]
        #expect(SunriseGate.pages(steps: steps, morningPrompts: [blank], lastNightNote: nil)
            .isEmpty)
    }

    @Test("Readiness keeps the scale the person chose for it")
    func readinessScale() {
        var prompts = ReflectionDefaults.morningPrompts
        prompts[1].ratingMax = 10
        let steps = [SunriseStep(kind: .readiness, isEnabled: true, isRequired: false)]
        let page = SunriseGate.pages(steps: steps, morningPrompts: prompts, lastNightNote: nil)
            .first
        #expect(page?.prompt?.ratingMax == 10)
    }

    @Test("Nothing enabled means no gate")
    func empty() {
        let steps = defaults.map { SunriseStep(
            kind: $0.kind,
            isEnabled: false,
            isRequired: $0.isRequired
        ) }
        #expect(SunriseGate.pages(steps: steps, morningPrompts: [], lastNightNote: "a").isEmpty)
    }

    @Test("Any non-empty answer satisfies a required text step; skippable steps always advance")
    func advancing() {
        let required = SunriseGatePage(note: nil, prompt: custom, isRequired: true)
        #expect(!required.canAdvance(with: nil))
        #expect(!required.canAdvance(with: .text("   \n")))
        #expect(required.canAdvance(with: .text("x")))
        let rating = SunriseGatePage(
            note: nil, prompt: ReflectionPrompt(text: "r", kind: .rating), isRequired: true
        )
        #expect(!rating.canAdvance(with: nil))
        #expect(rating.canAdvance(with: .rating(value: 1, scale: 5)))
        let optional = SunriseGatePage(note: nil, prompt: custom, isRequired: false)
        #expect(optional.canAdvance(with: nil))
        let noteOnly = SunriseGatePage(note: "a", prompt: nil, isRequired: false)
        #expect(noteOnly.canAdvance(with: nil))
    }
}

/// Last night's note and today's one thing, read from saved reflections.
struct SunriseDayTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return result
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func evening(_ at: String, left: String) -> Reflection {
        Reflection(timestamp: date(at), gate: .evening, answers: [
            ReflectionAnswer(
                promptID: ReflectionDefaults.leftForNextTimePromptID,
                promptTextSnapshot: "What would you like to continue next time?",
                value: .text(left)
            )
        ])
    }

    private func morning(_ at: String, oneThing: String) -> Reflection {
        Reflection(timestamp: date(at), gate: .morning, answers: [
            ReflectionAnswer(
                promptID: JournalPromptIDs.oneThing, promptTextSnapshot: SunriseVoice.question,
                value: .text(oneThing)
            )
        ])
    }

    @Test("Last night's note is the latest evening answer for next time")
    func lastNightNote() {
        let now = date("2026-11-17T07:04:00-08:00")
        let note = SunriseNote.lastNight(
            in: [
                evening("2026-11-15T18:00:00-08:00", left: "old"),
                evening("2026-11-16T18:00:00-08:00", left: "  pick up the retry test \n")
            ],
            now: now
        )
        #expect(note == "pick up the retry test")
    }

    @Test("A note from Friday still greets Monday, but not one from last week")
    func noteAge() {
        let monday = date("2026-11-16T07:00:00-08:00")
        #expect(SunriseNote.lastNight(
            in: [evening("2026-11-13T18:00:00-08:00", left: "friday")], now: monday
        ) == "friday")
        #expect(SunriseNote.lastNight(
            in: [evening("2026-11-09T18:00:00-08:00", left: "old")], now: monday
        ) == nil)
    }

    @Test("An empty or missing answer gives no note")
    func emptyNote() {
        let now = date("2026-11-17T07:04:00-08:00")
        #expect(SunriseNote.lastNight(
            in: [evening("2026-11-16T18:00:00-08:00", left: " ")], now: now
        ) == nil)
        #expect(SunriseNote.lastNight(in: [], now: now) == nil)
    }

    @Test("Today's one thing is the latest morning answer today")
    func oneThingToday() {
        let now = date("2026-11-17T09:00:00-08:00")
        let reflections = [
            morning("2026-11-16T07:00:00-08:00", oneThing: "yesterday"),
            morning("2026-11-17T07:05:00-08:00", oneThing: " Ship the billing migration ")
        ]
        #expect(SunriseDay.oneThing(in: reflections, now: now, calendar: calendar)
            == "Ship the billing migration")
        #expect(SunriseDay.isComplete(in: reflections, now: now, calendar: calendar))
        #expect(!SunriseDay.isComplete(
            in: [reflections[0]], now: now, calendar: calendar
        ))
        #expect(SunriseDay.oneThing(in: [reflections[0]], now: now, calendar: calendar) == nil)
    }
}
