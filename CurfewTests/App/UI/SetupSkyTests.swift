import CoreGraphics
@testable import Curfew
import CurfewAtmosphere
import Foundation
import Testing

/// Setup's sky is a story that only runs forward: each screen rests on its own
/// hour, and moving on is always later the same day or the next one.
struct SetupSkyStoryTests {
    @Test("The questions rest just after sunset and the summary rests at night")
    func restingHours() {
        let curfew = SetupSky.dayLength
        #expect(SetupSky.restingMinute(for: .schedule) > curfew)
        #expect(SetupSky.restingMinute(for: .schedule) < curfew + 30)
        #expect(SetupSky.restingMinute(for: .permissions) > SetupSky.restingMinute(for: .schedule))
        #expect(SetupSky.restingMinute(for: .optional) > SetupSky.restingMinute(for: .permissions))
        #expect(SetupSky.restingMinute(for: .ready) >= curfew + 60)
        #expect(SetupSky.restingMinute(for: .extras) == SetupSky.restingMinute(for: .ready))
        // The welcome and the morning question rest just before sunrise.
        #expect(SetupSky.restingMinute(for: .welcome) > 1440 - 15)
        #expect(SetupSky.restingMinute(for: .morning) == SetupSky.restingMinute(for: .welcome))
    }

    @Test("Moving on is later the same day, or the next day")
    func forwardOnly() {
        let dawn = SetupSky.restingMinute(for: .welcome)
        let dusk = SetupSky.restingMinute(for: .schedule)
        // From this dawn the next dusk is later today, not the one before it.
        let toDusk = SetupSky.next(after: dawn, toward: dusk)
        #expect(toDusk > dawn)
        #expect(toDusk - dawn < 1440)
        // From dusk the morning question is the next dawn.
        let toDawn = SetupSky.next(after: toDusk, toward: dawn)
        #expect(toDawn > toDusk)
        #expect(toDawn - toDusk < 1440)
    }

    @Test("A step back of a few minutes goes back, not round the whole day")
    func smallStepsBack() {
        let permissions = SetupSky.restingMinute(for: .permissions)
        let schedule = SetupSky.restingMinute(for: .schedule)
        #expect(SetupSky.next(after: permissions, toward: schedule) == schedule)
    }

    @Test("A sweep starts where the sky is and ends on the screen's hour")
    func sweep() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var story = SetupSkyStory(restingOn: .welcome)
        let dawn = story.minute(at: start)
        #expect(dawn == SetupSky.restingMinute(for: .welcome))

        let distance = story.move(to: .schedule, at: start, animated: true)

        #expect(distance > 0)
        #expect(story.minute(at: start) == dawn)
        let halfway = story.minute(at: start.addingTimeInterval(story.duration / 2))
        #expect(halfway > dawn)
        #expect(halfway < dawn + distance)
        #expect(story.minute(at: story.settlesAt) == dawn + distance)
        #expect(story.duration >= 0.9)
        #expect(story.duration <= 2.2)
    }

    @Test("Without motion the sky is already there")
    func still() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var story = SetupSkyStory(restingOn: .welcome)
        story.move(to: .ready, at: start, animated: false)
        #expect(story.duration == 0)
        #expect(SetupSky.wrapped(story.minute(at: start)) == SetupSky.restingMinute(for: .ready))
    }

    @Test("The welcome plays one day and night and ends on the welcome's own sky")
    func intro() {
        var last = SetupSky.Intro.minute(at: 0)
        #expect(last < 0)
        for tick in 1 ... 140 {
            let now = SetupSky.Intro.minute(at: Double(tick) / 10)
            #expect(now >= last)
            last = now
        }
        #expect(SetupSky.Intro.minute(at: SetupSky.Intro.duration)
            == SetupSky.restingMinute(for: .welcome))
        #expect(SetupSky.Intro.caption(at: 0) == nil)
        #expect(SetupSky.Intro.caption(at: 3) == 0)
        #expect(SetupSky.Intro.caption(at: 8) == 1)
        #expect(SetupSky.Intro.caption(at: 11) == 2)
    }
}

/// Warm white text reads on every sky setup rests on. The view keeps its text
/// inside ``SetupSky/textBand``; these skies are fixed, so this is the whole
/// proof.
struct SetupSkyContrastTests {
    private static let windows = [
        CGSize(width: 720, height: 520), CGSize(width: 1100, height: 760)
    ]

    @Test("Every resting screen gives small text 4.5 to 1", arguments: SetupScene.allCases)
    func restingScreensAreReadable(scene: SetupScene) {
        let frame = SetupSky.frame(
            at: SetupSky.restingMinute(for: scene),
            moonDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        for window in Self.windows {
            let lowest = SetupSky.lowestContrast(frame: frame, window: window)
            #expect(lowest >= 4.5, "\(scene) at \(window): \(lowest)")
        }
    }

    @Test("The check can fail: midday is not readable")
    func middayFails() {
        let noon = SetupSky.frame(
            at: SetupSky.dayLength / 2, moonDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(SetupSky.lowestContrast(frame: noon, window: Self.windows[0]) < 4.5)
    }

    @Test("The primary button's own fill carries its label")
    func primaryButton() {
        #expect(SetupSky.contrast(SetupSky.ink, SetupSky.primaryFill) >= 4.5)
    }
}
