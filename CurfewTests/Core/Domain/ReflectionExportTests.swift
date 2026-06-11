@testable import Curfew
import Foundation
import Testing

/// Tests for ``ReflectionExport`` — the Markdown and JSON serialisers behind the
/// Journal's export menu. Cover multiple rating questions and a configurable
/// scale so the "n/max" rendering and the JSON `max` field are exercised.
struct ReflectionExportTests {
    private func sample() -> [Reflection] {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        return [
            Reflection(
                timestamp: day,
                gate: .morning,
                answers: [
                    ReflectionAnswer(
                        promptID: UUID(),
                        promptTextSnapshot: "Focus today?",
                        value: .text("Ship the polish pass.")
                    ),
                    ReflectionAnswer(
                        promptID: UUID(),
                        promptTextSnapshot: "Readiness?",
                        value: .rating(value: 4, scale: 5)
                    )
                ]
            ),
            Reflection(
                timestamp: day.addingTimeInterval(8 * 60 * 60),
                gate: .evening,
                answers: [
                    ReflectionAnswer(
                        promptID: UUID(),
                        promptTextSnapshot: "Energy out of ten?",
                        value: .rating(value: 7, scale: 10)
                    )
                ]
            )
        ]
    }

    @Test("Markdown export includes day headings, gates, and n/max ratings")
    func markdown() {
        let document = ReflectionExport.markdown(sample())
        #expect(document.hasPrefix("# Reflections"))
        #expect(document.contains("### Morning"))
        #expect(document.contains("### Evening"))
        #expect(document.contains("Ship the polish pass."))
        #expect(document.contains("**Readiness?** 4/5"))
        #expect(document.contains("**Energy out of ten?** 7/10"))
    }

    @Test("Empty input still yields a well-formed Markdown document")
    func markdownEmpty() {
        #expect(ReflectionExport.markdown([]).hasPrefix("# Reflections"))
    }

    @Test("JSON export carries the rating value and its max")
    func json() throws {
        let json = ReflectionExport.json(sample())
        let data = Data(json.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let reflections = try #require(parsed?["reflections"] as? [[String: Any]])
        #expect(reflections.count == 2)

        // The 1–10 rating answer should report value 7 and max 10.
        let answers = reflections
            .flatMap { ($0["answers"] as? [[String: Any]]) ?? [] }
        let tenScale = answers.first { ($0["max"] as? Int) == 10 }
        #expect(tenScale?["value"] as? Int == 7)
        #expect(tenScale?["type"] as? String == "rating")
    }
}
