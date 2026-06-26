@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Behaviour tests for `ReflectionStore`, the SQLite-backed reflection log.
/// Each test opens its own database via
/// `ReflectionTestSupport.makeEphemeralStore(label:)`.
@MainActor
struct ReflectionStoreTests {
    private func sampleReflection(
        at timestamp: Date,
        gate: ReflectionGate
    ) -> Reflection {
        Reflection(
            timestamp: timestamp,
            gate: gate,
            answers: [
                ReflectionAnswer(
                    promptID: UUID(),
                    promptTextSnapshot: "What matters most today?",
                    value: .text("Ship the reflection feature.")
                ),
                ReflectionAnswer(
                    promptID: UUID(),
                    promptTextSnapshot: "How did today go?",
                    value: .rating(value: 4, scale: 5)
                ),
                ReflectionAnswer(
                    promptID: UUID(),
                    promptTextSnapshot: "Mood?",
                    value: .mood(.good)
                )
            ]
        )
    }

    @Test("A reflection round-trips through the store with every value type")
    func roundTrip() throws {
        let store = try ReflectionTestSupport.makeEphemeralStore(label: "roundtrip")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reflection = sampleReflection(at: now, gate: .evening)

        try store.append(reflection)

        let fetched = try store.reflections(
            in: now.addingTimeInterval(-60) ... now.addingTimeInterval(60)
        )
        #expect(fetched.count == 1)
        let restored = try #require(fetched.first)
        #expect(restored.id == reflection.id)
        #expect(restored.gate == .evening)
        #expect(restored.answers.count == 3)
        #expect(restored.answers[0].value == .text("Ship the reflection feature."))
        #expect(restored.answers[1].value == .rating(value: 4, scale: 5))
        #expect(restored.answers[2].value == .mood(.good))
        #expect(restored.answers[0].promptTextSnapshot == "What matters most today?")
    }

    @Test("Reflections outside the requested range are excluded")
    func dateRangeFilter() throws {
        let store = try ReflectionTestSupport.makeEphemeralStore(label: "range")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try store.append(sampleReflection(at: base, gate: .morning))
        try store.append(
            sampleReflection(at: base.addingTimeInterval(7 * 24 * 60 * 60), gate: .evening)
        )

        let onlyFirst = try store.reflections(
            in: base.addingTimeInterval(-60) ... base.addingTimeInterval(60)
        )
        #expect(onlyFirst.count == 1)
        #expect(onlyFirst.first?.gate == .morning)
    }

    @Test("Reflections come back ordered ascending by timestamp")
    func ordering() throws {
        let store = try ReflectionTestSupport.makeEphemeralStore(label: "order")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try store.append(sampleReflection(at: base.addingTimeInterval(120), gate: .evening))
        try store.append(sampleReflection(at: base, gate: .morning))

        let all = try store.reflections(
            in: base.addingTimeInterval(-60) ... base.addingTimeInterval(600)
        )
        #expect(all.map(\.gate) == [.morning, .evening])
    }

    @Test("Appending a duplicate id raises duplicateReflectionID")
    func duplicateID() throws {
        let store = try ReflectionTestSupport.makeEphemeralStore(label: "dupe")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reflection = sampleReflection(at: now, gate: .morning)
        try store.append(reflection)

        #expect(throws: ReflectionStoreError.duplicateReflectionID) {
            try store.append(reflection)
        }
    }

    @Test("Trim removes reflections older than the retention window")
    func trim() throws {
        let store = try ReflectionTestSupport.makeEphemeralStore(label: "trim")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = now.addingTimeInterval(-60 * 24 * 60 * 60)
        try store.append(sampleReflection(at: old, gate: .morning))
        try store.append(sampleReflection(at: now, gate: .evening))

        try store.trimReflections(olderThan: 52 * 7 * 24 * 60 * 60, now: now)
        let remaining = try store.reflections(
            in: old.addingTimeInterval(-60) ... now.addingTimeInterval(60)
        )
        // 60 days is inside the 52-week window, so both survive.
        #expect(remaining.count == 2)

        try store.trimReflections(olderThan: 30 * 24 * 60 * 60, now: now)
        let afterTighterTrim = try store.reflections(
            in: old.addingTimeInterval(-60) ... now.addingTimeInterval(60)
        )
        #expect(afterTighterTrim.count == 1)
        #expect(afterTighterTrim.first?.gate == .evening)
    }
}
