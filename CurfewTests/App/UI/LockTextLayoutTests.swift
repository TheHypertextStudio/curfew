import CoreGraphics
@testable import Curfew
import CurfewAtmosphere
import CurfewKit
import Foundation
import Testing

/// The sun and moon never sit behind the clock, the headline or the unlock
/// line: over a whole night, at every supported window size, no visible
/// body's disc meets the words' block.
@MainActor
struct LockTextLayoutTests {
    private static let sizes: [CGSize] = [
        CGSize(width: 1440, height: 900), CGSize(width: 1280, height: 800),
        CGSize(width: 1512, height: 982), CGSize(width: 1920, height: 1080),
        CGSize(width: 2560, height: 1440), CGSize(width: 1024, height: 768),
        CGSize(width: 3440, height: 1440), CGSize(width: 1080, height: 1920),
        CGSize(width: 960, height: 600)
    ]

    private static let words: [(headline: String, line: String?)] = [
        ("That's the day.", "Unlocks at 12:00 AM"),
        ("Nearly morning.", "Unlocks in 12 minutes"),
        ("That's the day.", "The unlock time has passed. This Mac is still locked.")
    ]

    private static func nights() -> [HorizonMoment] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        }
        return [
            HorizonMoment(
                now: date(16, 18),
                dayStart: date(16, 7),
                curfew: date(16, 18),
                nextUnlock: date(17, 7)
            ),
            HorizonMoment(
                now: date(16, 23),
                dayStart: date(16, 9),
                curfew: date(16, 23),
                nextUnlock: date(17, 3)
            )
        ]
    }

    @Test("No visible disc meets the words at any supported size, through the whole night")
    func bodiesClearTheWords() {
        for size in Self.sizes {
            for compact in [false, true] {
                for words in Self.words {
                    let layout = LockTextLayout.resolve(
                        size: size,
                        content: LockTextContent(
                            clock: "12:59", period: "PM", headline: words.headline, line: words.line
                        ),
                        compact: compact
                    )
                    #expect(layout.block.maxY <= size.height * (1 - HorizonGeometry.horizon))
                    for night in Self.nights() {
                        assertClear(layout.block, size: size, night: night)
                    }
                }
            }
        }
    }

    @Test("The block keeps its prototype place when the path allows it")
    func prototypePlacement() {
        let size = CGSize(width: 1440, height: 900)
        let layout = LockTextLayout.resolve(
            size: size,
            content: LockTextContent(
                clock: "9:41", period: "PM", headline: "That's the day.", line: "Unlocks at 7:00 AM"
            ),
            compact: false
        )
        #expect(layout.block.minY >= size.height * 0.2)
        #expect(layout.clockSize > size.height * 0.15)
        #expect(abs(layout.block.midX - size.width / 2) < 1)
    }

    private func assertClear(_ block: CGRect, size: CGSize, night: HorizonMoment) {
        var moment = night
        var now = night.curfew
        while now < night.nextUnlock {
            moment.now = now
            let frame = LockSceneSky.frame(for: moment)
            let bodies = [
                Body(point: frame.sun, weight: frame.sunWeight, radius: HorizonGeometry.sunRadius),
                Body(
                    point: frame.moon,
                    weight: frame.moonWeight,
                    radius: HorizonGeometry.moonRadius
                )
            ]
            for body in bodies where body.weight > 0.001 {
                let (point, radius) = (body.point, body.radius)
                let center = CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
                let distance = LockTextLayout.distance(from: center, to: block)
                #expect(
                    distance >= radius * size.height,
                    "\(size) \(now): disc at \(center) meets \(block)"
                )
            }
            now = now.addingTimeInterval(5 * 60)
        }
    }

    private struct Body {
        let point: HorizonPoint
        let weight: Double
        let radius: Double
    }
}
