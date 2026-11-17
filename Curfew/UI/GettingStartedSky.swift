import CoreGraphics
import CurfewAtmosphere
import Foundation

/// The screens setup can rest on. Each has its own hour of the sky.
enum SetupScene: Equatable, CaseIterable, Sendable {
    /// The welcome, once its day has played.
    case welcome
    /// When should your day end?
    case schedule
    /// When does this Mac open again, and on which days.
    case morning
    case permissions
    case optional
    case ready
    case extras
}

/// Setup's sky. It is a story, not the time outside: a fixed day from 7:00 to
/// 18:00 that only runs forward. Every screen rests in twilight or at night,
/// where warm white text always has its contrast; daylight is seen only while
/// the welcome plays and while the sky moves between screens.
enum SetupSky {
    /// The story day's length in minutes, from unlock to curfew.
    static let dayLength = 660.0
    /// Minutes from one unlock to the next.
    static let day = 1440.0

    /// The sky is drawn this much taller than the window and anchored at the
    /// top, which puts the horizon just below the window's bottom edge. Setup
    /// keeps nothing on the ground, so the window is all sky: the sun sets
    /// and rises at its bottom edge.
    static let heightScale = 1.36

    /// Where every piece of setup's text sits, as a share of the window from
    /// its top left corner. The contrast tests sample all of it.
    static let textBand = CGRect(x: 0.11, y: 0.16, width: 0.78, height: 0.62)

    /// Warm white, the ink over the sky.
    static let ink = HorizonRGB(0.99, 0.97, 0.94)
    /// The primary button's fill: ember, dark enough for its own label.
    static let primaryFill = HorizonRGB(0.749, 0.294, 0.110)

    /// The hour a screen rests on, in minutes since the story day's unlock.
    static func restingMinute(for scene: SetupScene) -> Double {
        switch scene {
        // Just before sunrise.
        case .welcome, .morning: day - 9
        // A quarter hour after sunset, a little later on each screen.
        case .schedule: dayLength + 15
        case .permissions: dayLength + 17
        case .optional: dayLength + 19
        // The middle of the night, with the moon high above the heading.
        case .ready, .extras: dayLength + 390
        }
    }

    /// A story minute as a time of day, from 0 up to one day.
    static func wrapped(_ minute: Double) -> Double {
        let remainder = minute.truncatingRemainder(dividingBy: day)
        return remainder < 0 ? remainder + day : remainder
    }

    /// The next time the sky reaches `resting` from `current`: later the same
    /// day, or the next day. A step back of less than four hours goes back
    /// instead of round the whole day.
    static func next(after current: Double, toward resting: Double) -> Double {
        var delta = wrapped(resting - current)
        if delta > day - 240 {
            delta -= day
        }
        return current + delta
    }

    /// How long the sky takes to travel `distance` minutes, in seconds.
    static func sweepDuration(distance: Double) -> Double {
        min(2.2, max(0.9, 0.9 + abs(distance) / day * 2))
    }

    /// How long the next screen waits before arriving, so it lands as the
    /// sky settles and not while the sun is crossing behind it.
    static func entranceDelay(distance: Double) -> Double {
        abs(distance) < 90 ? 0.32 : sweepDuration(distance: distance) * 0.55
    }

    /// The sky at a story minute, with the moon in `moonDate`'s real phase.
    static func frame(at storyMinute: Double, moonDate: Date) -> HorizonFrame {
        let unlock = Date(timeIntervalSinceReferenceDate: 0)
        var frame = HorizonMoment(
            now: unlock.addingTimeInterval(wrapped(storyMinute) * 60),
            dayStart: unlock,
            curfew: unlock.addingTimeInterval(dayLength * 60),
            nextUnlock: unlock.addingTimeInterval(day * 60)
        ).frame
        frame.moonPhase = HorizonMoment.moonPhaseAngle(at: moonDate)
        return frame
    }

    /// WCAG contrast ratio between two sRGB colours.
    static func contrast(_ first: HorizonRGB, _ second: HorizonRGB) -> Double {
        TodaySkyLegibility.contrast(first, second)
    }

    /// The lowest contrast warm white text has anywhere in ``textBand`` on
    /// `frame`, in a setup window of `window`, across the drifting bands.
    static func lowestContrast(
        frame: HorizonFrame, window: CGSize, palette: HorizonPalette = .standard
    ) -> Double {
        let skyHeight = Double(window.height) * heightScale
        let canvas = HorizonField.Canvas(
            aspect: Double(window.width) / skyHeight, pixelHeight: skyHeight
        )
        var lowest = Double.greatestFiniteMagnitude
        for phase in [0.0, 0.25, 0.5, 0.75] {
            let bands = HorizonField.Bands(phase: phase, edgeWidth: 0)
            for column in 0 ..< 48 {
                for row in 0 ..< 32 {
                    let across = textBand.minX + textBand.width * Double(column) / 47
                    let down = textBand.minY + textBand.height * Double(row) / 31
                    let point = HorizonPoint(x: across, y: 1 - down / heightScale)
                    let sky = HorizonField.color(
                        at: point, canvas: canvas, frame: frame, bands: bands, palette: palette
                    )
                    lowest = min(lowest, contrast(ink, sky))
                }
            }
        }
        return lowest
    }

    /// The welcome's day: a title card before dawn, a working day, curfew and
    /// night, then the next dawn, where the welcome rests.
    enum Intro {
        /// Seconds from the window opening to the resting welcome.
        static let duration = 13.0
        /// When the title card settles into the small mark.
        static let titleSettles = 1.5
        /// When each caption arrives, in seconds.
        static let captionTimes = [2.5, 6.9, 10.5]

        private static let keys: [(time: Double, minute: Double)] = [
            (0, -75), (1.7, -50), (3.4, 45), (6.4, dayLength - 12), (8.4, dayLength + 78),
            (9.5, dayLength + 118), (11.8, restingMinute(for: .welcome)),
            (duration, restingMinute(for: .welcome))
        ]

        private static func keyed(_ time: Double) -> Double {
            let clamped = min(max(time, 0), duration)
            var index = 0
            while index < keys.count - 2, clamped > keys[index + 1].time {
                index += 1
            }
            let start = keys[index]
            let end = keys[index + 1]
            let unit = (clamped - start.time) / (end.time - start.time)
            return start.minute + (end.minute - start.minute) * min(max(unit, 0), 1)
        }

        /// The story minute `elapsed` seconds in. The keyed pace is averaged
        /// over two fifths of a second so the sky never changes speed abruptly.
        static func minute(at elapsed: Double) -> Double {
            let offsets = [-0.2, -0.1, 0, 0.1, 0.2]
            return offsets.reduce(0) { $0 + keyed(elapsed + $1) } / Double(offsets.count)
        }

        /// The caption showing `elapsed` seconds in, or `nil` before the first.
        static func caption(at elapsed: Double) -> Int? {
            captionTimes.lastIndex { elapsed >= $0 }
        }
    }
}

/// Where setup's sky is, and where it is going.
///
/// A plain value: `minute(at:)` is a pure function of the date, so the sky is
/// drawn straight from it and the sweeps are unit tested without a run loop.
struct SetupSkyStory: Equatable {
    private var origin: Double
    private var target: Double
    private var start: Date
    /// Seconds the current sweep takes; zero when the sky is at rest.
    private(set) var duration: TimeInterval

    init(restingOn scene: SetupScene) {
        self.init(at: SetupSky.restingMinute(for: scene))
    }

    /// A sky already at `minute`, such as where the welcome's day was stopped.
    init(at minute: Double) {
        self.origin = minute
        self.target = minute
        self.start = .distantPast
        self.duration = 0
    }

    /// When the current sweep ends.
    var settlesAt: Date {
        start.addingTimeInterval(duration)
    }

    func minute(at date: Date) -> Double {
        guard duration > 0, date < settlesAt else { return target }
        let unit = max(date.timeIntervalSince(start) / duration, 0)
        let eased = unit < 0.5 ? 4 * unit * unit * unit : 1 - pow(-2 * unit + 2, 3) / 2
        return origin + (target - origin) * eased
    }

    /// Sends the sky on to `scene`'s hour from wherever it is now. Returns the
    /// distance in story minutes; without motion the sky is simply there.
    @discardableResult
    mutating func move(to scene: SetupScene, at date: Date, animated: Bool) -> Double {
        let current = minute(at: date)
        let next = SetupSky.next(after: current, toward: SetupSky.restingMinute(for: scene))
        let distance = next - current
        let sweeps = animated && abs(distance) > 0.5
        origin = sweeps ? current : next
        target = next
        start = date
        duration = sweeps ? SetupSky.sweepDuration(distance: distance) : 0
        return distance
    }
}
