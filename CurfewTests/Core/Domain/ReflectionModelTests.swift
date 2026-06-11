@testable import Curfew
import Foundation
import Testing

/// Tests for the pure reflection value types and the persisted configuration:
/// the `ReflectionValue` tagged-envelope coding, answer round-trips, and
/// `ReflectionConfiguration` defaults / lenient decoding.
struct ReflectionModelTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Test("Every ReflectionValue case round-trips through Codable")
    func valueCodableRoundTrip() throws {
        let cases: [ReflectionValue] = [
            .text("a multi-line\nnote with \"quotes\""),
            .rating(value: 5, scale: 5),
            .mood(.rough)
        ]
        for value in cases {
            let data = try encoder.encode(value)
            let restored = try decoder.decode(ReflectionValue.self, from: data)
            #expect(restored == value)
        }
    }

    @Test("An answer array round-trips, preserving prompt snapshots")
    func answersRoundTrip() throws {
        let answers = [
            ReflectionAnswer(
                promptID: UUID(),
                promptTextSnapshot: "Focus?",
                value: .text("One thing.")
            ),
            ReflectionAnswer(
                promptID: UUID(),
                promptTextSnapshot: "Score?",
                value: .rating(value: 3, scale: 5)
            )
        ]
        let data = try encoder.encode(answers)
        let restored = try decoder.decode([ReflectionAnswer].self, from: data)
        #expect(restored == answers)
    }

    @Test("ReflectionValue.kind reports the matching prompt kind")
    func valueKindMapping() {
        #expect(ReflectionValue.text("x").kind == .text)
        #expect(ReflectionValue.rating(value: 2, scale: 5).kind == .rating)
        #expect(ReflectionValue.mood(.neutral).kind == .mood)
    }

    @Test("Mood scores are ordered 1...5 worst to best")
    func moodScores() {
        #expect(ReflectionMood.rough.score == 1)
        #expect(ReflectionMood.great.score == 5)
        let ordered = ReflectionMood.allCases.map(\.score)
        #expect(ordered == [1, 2, 3, 4, 5])
    }

    @Test("Default configuration enables both gates with the default prompts")
    func defaultConfiguration() {
        let config = ReflectionConfiguration.default
        #expect(config.morningEnabled)
        #expect(config.eveningEnabled)
        #expect(config.morningPrompts == ReflectionDefaults.morningPrompts)
        #expect(config.eveningPrompts == ReflectionDefaults.eveningPrompts)
        #expect(config.isEnabled(.morning))
        #expect(config.prompts(for: .evening) == ReflectionDefaults.eveningPrompts)
    }

    @Test("Configuration round-trips through Codable")
    func configurationRoundTrip() throws {
        var config = ReflectionConfiguration.default
        config.eveningEnabled = false
        config.morningPrompts = [ReflectionPrompt(text: "Custom?", kind: .mood)]

        let data = try encoder.encode(config)
        let restored = try decoder.decode(ReflectionConfiguration.self, from: data)
        #expect(restored == config)
    }

    @Test("A partial configuration payload decodes with defaults filled in")
    func lenientDecoding() throws {
        // Only `morningEnabled` present — every other field should default.
        let json = Data(#"{"morningEnabled": false}"#.utf8)
        let restored = try decoder.decode(ReflectionConfiguration.self, from: json)
        #expect(restored.morningEnabled == false)
        #expect(restored.eveningEnabled == true)
        #expect(restored.morningPrompts == ReflectionDefaults.morningPrompts)
        #expect(restored.eveningPrompts == ReflectionDefaults.eveningPrompts)
    }

    @Test("Settings store returns the default configuration when none is saved")
    func storeDefaultsWhenEmpty() {
        let suite = "studio.hypertext.curfew.tests.reflcfg.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = CurfewSettingsStore(defaults: defaults)
        #expect(store.loadReflectionConfiguration() == .default)
    }

    @Test("Settings store round-trips an edited configuration")
    func storeRoundTrip() {
        let suite = "studio.hypertext.curfew.tests.reflcfg.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = CurfewSettingsStore(defaults: defaults)

        var config = ReflectionConfiguration.default
        config.morningEnabled = false
        config.eveningPrompts = [ReflectionPrompt(text: "Wins?", kind: .text)]
        store.saveReflectionConfiguration(config)

        #expect(store.loadReflectionConfiguration() == config)
    }

    @Test("Morning defaults are neutral: text + rating, no mood")
    func neutralMorningDefaults() {
        let kinds = ReflectionDefaults.morningPrompts.map(\.kind)
        #expect(kinds == [.text, .rating])
        #expect(!kinds.contains(.mood))
    }

    @Test("A prompt persisted before ratingMax existed decodes to a scale of 5")
    func promptRatingMaxUpgrade() throws {
        // Legacy payload with no `ratingMax` key.
        let legacy = Data(#"""
        {"id":"\#(UUID().uuidString)","text":"How did it go?","kind":"rating"}
        """#.utf8)
        let restored = try decoder.decode(ReflectionPrompt.self, from: legacy)
        #expect(restored.ratingMax == 5)
        #expect(restored.kind == .rating)
    }

    @Test("A configurable rating scale round-trips on the prompt and the value")
    func configurableScaleRoundTrip() throws {
        let prompt = ReflectionPrompt(text: "1–10 day", kind: .rating, ratingMax: 10)
        let restoredPrompt = try decoder.decode(
            ReflectionPrompt.self,
            from: encoder.encode(prompt)
        )
        #expect(restoredPrompt.ratingMax == 10)

        let value = ReflectionValue.rating(value: 8, scale: 10)
        let restoredValue = try decoder.decode(
            ReflectionValue.self,
            from: encoder.encode(value)
        )
        #expect(restoredValue == value)
    }

    @Test("A rating persisted before scale existed decodes to a scale of 5")
    func ratingValueScaleUpgrade() throws {
        let legacy = Data(#"{"type":"rating","rating":4}"#.utf8)
        let restored = try decoder.decode(ReflectionValue.self, from: legacy)
        #expect(restored == .rating(value: 4, scale: 5))
    }

    @Test("reflectionValueText renders ratings as n/max and moods by label")
    func valueText() {
        #expect(reflectionValueText(.rating(value: 3, scale: 10)) == "3/10")
        #expect(reflectionValueText(.mood(.good)) == "Good")
        #expect(reflectionValueText(.text("hi")) == "hi")
    }
}
