import Foundation

/// One rating question's week, for the Journal's neutral "Ratings this week"
/// trend: a label, the scale, and the value recorded on each day it was
/// answered. Mood answers fold in by their 1–5 score so the chart stays a
/// single neutral "ratings" axis (no mood branding).
struct RatingTrend: Identifiable {
    let id: UUID
    let label: String
    let scale: Int
    let points: [Date: Int]

    /// "avg n.n/max" across the days answered, or "—" when empty.
    var averageText: String {
        guard !points.isEmpty else { return "—" }
        let avg = Double(points.values.reduce(0, +)) / Double(points.count)
        return String(format: "avg %.1f/%d", avg, scale)
    }

    /// Builds one trend per numeric question (`.rating`, plus `.mood` by score),
    /// keyed by prompt id and labelled by the most recent prompt wording, sorted
    /// by label for a stable order.
    static func build(
        from reflections: [Reflection],
        calendar: Calendar = .current
    ) -> [RatingTrend] {
        struct Accumulator {
            var label = ""
            var scale = 5
            var points: [Date: Int] = [:]
            var lastSeen = Date.distantPast
        }
        var byPrompt: [UUID: Accumulator] = [:]

        for reflection in reflections {
            let day = calendar.startOfDay(for: reflection.timestamp)
            for answer in reflection.answers {
                let numeric: (value: Int, scale: Int)? = switch answer.value {
                case .rating(let value, let scale): (value, scale)
                case .mood(let mood): (mood.score, 5)
                case .text: nil
                }
                guard let numeric else { continue }
                var acc = byPrompt[answer.promptID] ?? Accumulator()
                acc.points[day] = numeric.value
                acc.scale = numeric.scale
                if reflection.timestamp >= acc.lastSeen {
                    acc.lastSeen = reflection.timestamp
                    acc.label = answer.promptTextSnapshot
                }
                byPrompt[answer.promptID] = acc
            }
        }

        return byPrompt
            .map {
                RatingTrend(
                    id: $0.key,
                    label: $0.value.label,
                    scale: $0.value.scale,
                    points: $0.value.points
                )
            }
            .sorted { $0.label < $1.label }
    }
}
