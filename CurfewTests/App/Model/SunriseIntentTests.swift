@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// The Sunrise intents read today's one thing and whether Sunrise is complete
/// from the reflection log, and read a missing log as no answer yet.
struct SunriseIntentTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("Today's one thing and completion come from this morning's answer")
    func readsToday() {
        let morning = Reflection(timestamp: now.addingTimeInterval(-600), gate: .morning, answers: [
            ReflectionAnswer(
                promptID: JournalPromptIDs.oneThing, promptTextSnapshot: SunriseVoice.question,
                value: .text("Ship it")
            )
        ])
        #expect(SunriseIntentSupport.today(in: [morning], now: now)
            == .init(oneThing: "Ship it", isComplete: true))
        #expect(SunriseIntentSupport.today(in: [], now: now)
            == .init(oneThing: nil, isComplete: false))
    }

    @Test("A missing reflection log reads as no answer yet")
    func missingLog() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-reflections-\(UUID().uuidString).sqlite")
        #expect(SunriseIntentSupport.loadToday(now: now, databaseURL: missing)
            == .init(oneThing: nil, isComplete: false))
    }
}
