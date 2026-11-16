import AppKit
@testable import Curfew
import Testing

/// The menu bar icon is a sun over a line: lower as curfew nears, resting on
/// the line in the last half hour, absent while locked, rising on the left at
/// Sunrise. Geometry is in the prototype's 22 by 18 point canvas, y down.
struct HorizonMenuBarGlyphTests {
    @Test("The line spans the canvas at the horizon")
    func line() {
        let glyph = HorizonMenuBarGlyph(state: .locked)
        #expect(glyph.size == CGSize(width: 22, height: 18))
        #expect(glyph.lineStart == CGPoint(x: 2, y: 13.5))
        #expect(glyph.lineEnd == CGPoint(x: 20, y: 13.5))
        #expect(HorizonMenuBarGlyph.lineWidth == 1.6)
        #expect(HorizonMenuBarGlyph.sunRadius == 3.5)
    }

    @Test("While working the sun sits lower as curfew nears")
    func workingDescends() throws {
        let afternoon = try #require(HorizonMenuBarGlyph(state: .working(minutesToCurfew: 150))
            .sunCenter)
        #expect(afternoon == CGPoint(x: 13, y: 6))
        let later = try #require(HorizonMenuBarGlyph(state: .working(minutesToCurfew: 50))
            .sunCenter)
        #expect(later == CGPoint(x: 13, y: 10))
        let morning = try #require(HorizonMenuBarGlyph(state: .working(minutesToCurfew: 600))
            .sunCenter)
        #expect(morning.y == HorizonMenuBarGlyph.highestSun)
        #expect(morning.y - HorizonMenuBarGlyph.sunRadius >= 0)
    }

    @Test("In the last half hour the sun rests on the line")
    func lastHalfHour() throws {
        let center = try #require(HorizonMenuBarGlyph(state: .lastHalfHour).sunCenter)
        #expect(center == CGPoint(x: 13, y: 13.5))
    }

    @Test("Locked shows only the line, and Sunrise rises on the left")
    func lockedAndSunrise() throws {
        #expect(HorizonMenuBarGlyph(state: .locked).sunCenter == nil)
        let sunrise = try #require(HorizonMenuBarGlyph(state: .sunrise).sunCenter)
        #expect(sunrise == CGPoint(x: 7, y: 13.5))
    }

    @Test("States resolve from the countdown")
    func resolve() {
        #expect(HorizonMenuBarGlyph.State.resolve(
            isLocked: true,
            isSunrise: false,
            minutesToCurfew: 10
        ) == .locked)
        #expect(HorizonMenuBarGlyph.State.resolve(
            isLocked: false,
            isSunrise: true,
            minutesToCurfew: nil
        ) == .sunrise)
        #expect(HorizonMenuBarGlyph.State.resolve(
            isLocked: false,
            isSunrise: false,
            minutesToCurfew: 30
        ) == .lastHalfHour)
        #expect(
            HorizonMenuBarGlyph.State.resolve(
                isLocked: false,
                isSunrise: false,
                minutesToCurfew: 31
            )
                == .working(minutesToCurfew: 31)
        )
        #expect(
            HorizonMenuBarGlyph.State.resolve(
                isLocked: false,
                isSunrise: false,
                minutesToCurfew: nil
            )
                == .working(minutesToCurfew: .infinity)
        )
    }

    @Test("The rendered image is a template of the canvas size")
    func templateImage() {
        let image = HorizonMenuBarGlyph(state: .working(minutesToCurfew: 90)).image()
        #expect(image.isTemplate)
        #expect(image.size == CGSize(width: 22, height: 18))
        #expect(!image.accessibilityDescription.isNilOrEmpty)
    }
}

private extension String? {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
