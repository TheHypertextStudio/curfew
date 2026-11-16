import Foundation

// The scene frame is named as in the prototype and the spec: points are x and y,
// the span is x0 to x1.
// swiftlint:disable identifier_name

/// Fixed proportions of the Horizon scene, in the unit frame where x runs 0 to 1
/// left to right and y runs 0 to 1 bottom to top. These match the prototype
/// shader in `Documentation/design/horizon-prototype.html`.
public enum HorizonGeometry {
    /// Height of the horizon line.
    public static let horizon = 0.26
    /// Height of the quadratic path's control point. The path peaks at
    /// `0.5 * horizon + 0.5 * controlHeight`, which is 0.93.
    public static let controlHeight = 1.6
    /// Sun disc radius as a fraction of the scene height.
    public static let sunRadius = 0.05
    /// Moon disc radius as a fraction of the scene height.
    public static let moonRadius = 0.04
    /// Number of hard-edged brightness steps.
    public static let bandCount = 14
}

/// A point in the unit scene frame (y up).
public struct HorizonPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The horizontal stretch of the sky the sun and moon cross. Full-bleed
/// surfaces use ``fullBleed``; a surface with a sidebar passes its own span so
/// the path stays over the visible sky.
public struct HorizonSpan: Equatable, Sendable {
    public var x0: Double
    public var x1: Double

    public init(x0: Double, x1: Double) {
        self.x0 = x0
        self.x1 = x1
    }

    public static let fullBleed = HorizonSpan(x0: 0.07, x1: 0.93)

    /// The point at progress `t` along the quadratic from `(x0, horizon)`
    /// through `(mid, controlHeight)` to `(x1, horizon)`.
    public func point(at progress: Double) -> HorizonPoint {
        let rest = 1 - progress
        let mid = (x0 + x1) / 2
        let horizon = HorizonGeometry.horizon
        let start = rest * rest
        let control = 2 * progress * rest
        let end = progress * progress
        return HorizonPoint(
            x: start * x0 + control * mid + end * x1,
            y: start * horizon + control * HorizonGeometry.controlHeight + end * horizon
        )
    }
}

// swiftlint:enable identifier_name

/// Everything the shader needs for one instant: where the sun and moon are,
/// how strongly each lights the sky, the elevation that picks the palette, and
/// the moon's phase.
public struct HorizonFrame: Equatable, Sendable {
    public var sun: HorizonPoint
    /// 0 when the sun no longer lights the sky, 1 by day.
    public var sunWeight: Double
    public var moon: HorizonPoint
    /// 0 by day, 1 through the middle of the night.
    public var moonWeight: Double
    /// `sin(pi * p)` by day, down to -0.9 at night.
    public var elevation: Double
    /// Radians: 0 new moon, pi full moon.
    public var moonPhase: Double

    public init(
        sun: HorizonPoint, sunWeight: Double, moon: HorizonPoint, moonWeight: Double,
        elevation: Double, moonPhase: Double
    ) {
        self.sun = sun
        self.sunWeight = sunWeight
        self.moon = moon
        self.moonWeight = moonWeight
        self.elevation = elevation
        self.moonPhase = moonPhase
    }
}

/// The inputs of the sky: now, the working day's start, the effective curfew
/// (including any extension) and the next unlock. ``frame`` is the prototype's
/// `model()` ported exactly.
public struct HorizonMoment: Equatable, Sendable {
    public var now: Date
    /// When today's working day began: the scheduled unlock this morning.
    public var dayStart: Date
    /// The effective curfew, including any extension.
    public var curfew: Date
    /// The next scheduled unlock.
    public var nextUnlock: Date
    /// Length of the next working day, used once the sun rises after
    /// `nextUnlock`. The prototype uses the scheduled day (without extensions).
    public var nextDayLength: TimeInterval
    public var span: HorizonSpan

    public init(
        now: Date, dayStart: Date, curfew: Date, nextUnlock: Date,
        nextDayLength: TimeInterval? = nil, span: HorizonSpan = .fullBleed
    ) {
        self.now = now
        self.dayStart = dayStart
        self.curfew = curfew
        self.nextUnlock = nextUnlock
        self.nextDayLength = max(60, nextDayLength ?? curfew.timeIntervalSince(dayStart))
        self.span = span
    }

    public var frame: HorizonFrame {
        // Minutes, as in the prototype.
        let minute = now.timeIntervalSince(dayStart) / 60
        let start = 0.0
        let curfewMinute = curfew.timeIntervalSince(dayStart) / 60
        let unlockMinute = nextUnlock.timeIntervalSince(dayStart) / 60
        let dayLength = max(1, curfewMinute - start)
        let nextDay = nextDayLength / 60
        let night = max(1, unlockMinute - curfewMinute)
        let moonProgress = (minute - curfewMinute) / night

        let progress: Double
        let sunWeight: Double
        let elevation: Double
        var moonWeight = 0.0
        if minute <= curfewMinute {
            progress = (minute - start) / dayLength
            sunWeight = 1
            elevation = sin(.pi * max(0, progress))
        } else if minute < unlockMinute {
            elevation = -0.9 * min(1, (minute - curfewMinute) / 70, (unlockMinute - minute) / 35)
            if minute <= curfewMinute + 45 {
                progress = (minute - start) / dayLength
                sunWeight = 1 - smoothstep(curfewMinute + 5, curfewMinute + 45, minute)
            } else if minute >= unlockMinute - 40 {
                progress = (minute - unlockMinute) / nextDay
                sunWeight = smoothstep(unlockMinute - 40, unlockMinute - 5, minute)
            } else {
                progress = 1.2
                sunWeight = 0
            }
            moonWeight = min(
                smoothstep(curfewMinute + 5, curfewMinute + 50, minute),
                1 - smoothstep(unlockMinute - 50, unlockMinute - 10, minute)
            )
        } else {
            progress = (minute - unlockMinute) / nextDay
            sunWeight = 1
            elevation = sin(.pi * progress)
        }
        return HorizonFrame(
            sun: span.point(at: progress),
            sunWeight: sunWeight,
            moon: span.point(at: moonProgress),
            moonWeight: moonWeight,
            elevation: elevation,
            moonPhase: Self.moonPhaseAngle(at: now)
        )
    }
}

public extension HorizonMoment {
    /// Mean synodic month in days.
    static let synodicMonthDays = 29.530588853
    /// Julian date of the reference new moon, 2000-01-06 18:14 UTC.
    static let referenceNewMoonJulianDate = 2_451_550.259722

    /// The moon's phase angle on `date`: 0 at new moon, pi at full moon.
    static func moonPhaseAngle(at date: Date) -> Double {
        let julian = date.timeIntervalSince1970 / 86400 + 2_440_587.5
        let raw = (julian - referenceNewMoonJulianDate)
            .truncatingRemainder(dividingBy: synodicMonthDays)
        let age = (raw + synodicMonthDays).truncatingRemainder(dividingBy: synodicMonthDays)
        return 2 * .pi * age / synodicMonthDays
    }
}

/// GLSL `smoothstep`, including the degenerate equal-edge case as a step.
func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
    guard edge1 > edge0 else { return value < edge0 ? 0 : 1 }
    let unit = min(max((value - edge0) / (edge1 - edge0), 0), 1)
    return unit * unit * (3 - 2 * unit)
}

/// GLSL `mix`.
func mix(_ start: Double, _ end: Double, _ amount: Double) -> Double {
    start + (end - start) * amount
}

public extension HorizonMoment {
    /// A moment from the schedule: the effective curfew and the next unlock.
    /// The working day began at the next unlock's clock time one day earlier,
    /// which is when the sun rose.
    static func scheduled(
        now: Date, curfew: Date, nextUnlock: Date, nextDayLength: TimeInterval? = nil,
        span: HorizonSpan = .fullBleed, calendar: Calendar = .current
    ) -> HorizonMoment {
        var dayStart = calendar.date(byAdding: .day, value: -1, to: nextUnlock)
            ?? nextUnlock.addingTimeInterval(-86400)
        if dayStart >= curfew {
            // A schedule whose curfew falls before its own unlock clock time.
            dayStart = curfew.addingTimeInterval(-11 * 3600)
        }
        return HorizonMoment(
            now: now, dayStart: dayStart, curfew: curfew, nextUnlock: nextUnlock,
            nextDayLength: nextDayLength, span: span
        )
    }

    /// The still sky shown when no curfew is scheduled: the prototype's day,
    /// rising at 7 AM and setting at 6 PM.
    static func unscheduled(
        now: Date, span: HorizonSpan = .fullBleed, calendar: Calendar = .current
    ) -> HorizonMoment {
        let today = calendar.startOfDay(for: now)
        func at(_ hour: Int, daysFrom offset: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        let morning = at(7, daysFrom: 0)
        let curfew = now < morning ? at(18, daysFrom: -1) : at(18, daysFrom: 0)
        let unlock = now < morning ? morning : at(7, daysFrom: 1)
        return scheduled(
            now: now, curfew: curfew, nextUnlock: unlock, span: span, calendar: calendar
        )
    }
}

public extension HorizonMoment {
    /// The middle of a night with no schedule behind it: the sun long set and
    /// the moon high in tonight's real phase.
    static func restingNight(at now: Date, span: HorizonSpan = .fullBleed) -> HorizonMoment {
        HorizonMoment(
            now: now, dayStart: now.addingTimeInterval(-17 * 3600),
            curfew: now.addingTimeInterval(-6 * 3600), nextUnlock: now.addingTimeInterval(6 * 3600),
            span: span
        )
    }
}
