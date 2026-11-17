import Foundation

/// The lock's sky: the same scene after dark. The model alone takes seventy
/// minutes after curfew to reach night; the lock is night from the moment it
/// arrives, then follows the model exactly, including its warming toward
/// unlock. The app's lock windows and the bundled screen saver both draw this,
/// so a handoff between them shows one continuous scene.
public enum LockSceneSky {
    /// How long after curfew the model reaches full night.
    public static let nightfall: TimeInterval = 70 * 60
    /// How long before unlock the model starts the morning (the moon fades).
    public static let morningRamp: TimeInterval = 50 * 60

    /// The instant whose model frame the lock shows. Never earlier than now,
    /// never into the morning ramp, so the lead-in is the model's own.
    public static func sceneTime(for moment: HorizonMoment) -> Date {
        let now = moment.now
        guard now >= moment.curfew, now < moment.nextUnlock else { return now }
        var night = moment.curfew.addingTimeInterval(nightfall)
        let morning = moment.nextUnlock.addingTimeInterval(-morningRamp)
        if night > morning {
            night = max(moment.curfew, morning)
        }
        return max(now, night)
    }

    /// The lock's frame for `moment`, with tonight's real moon phase.
    public static func frame(for moment: HorizonMoment) -> HorizonFrame {
        var shifted = moment
        shifted.now = sceneTime(for: moment)
        var frame = shifted.frame
        frame.moonPhase = HorizonMoment.moonPhaseAngle(at: moment.now)
        return frame
    }

    /// A straight blend between two frames for the arrival move; `amount`
    /// is clamped to 0...1. The shader shifts high bands toward night first,
    /// so lowering the elevation cascades colour down from the top.
    public static func blend(
        _ start: HorizonFrame,
        _ end: HorizonFrame,
        amount: Double
    ) -> HorizonFrame {
        let unit = min(max(amount, 0), 1)
        if unit == 0 {
            return start
        }
        if unit == 1 {
            return end
        }
        func lerp(_ lower: Double, _ upper: Double) -> Double {
            lower + (upper - lower) * unit
        }
        return HorizonFrame(
            sun: HorizonPoint(x: lerp(start.sun.x, end.sun.x), y: lerp(start.sun.y, end.sun.y)),
            sunWeight: lerp(start.sunWeight, end.sunWeight),
            moon: HorizonPoint(
                x: lerp(start.moon.x, end.moon.x),
                y: lerp(start.moon.y, end.moon.y)
            ),
            moonWeight: lerp(start.moonWeight, end.moonWeight),
            elevation: lerp(start.elevation, end.elevation),
            moonPhase: end.moonPhase
        )
    }
}
