import Foundation

/// The bands' drift. They advance ``bandsPerSecond`` while the day is running
/// and hold still otherwise (locked, off, Reduce Motion). Stopping keeps the
/// current value and resuming continues from it, so the sky never jumps.
public struct HorizonBandPhase: Equatable, Sendable {
    public static let bandsPerSecond = 0.05
    /// The prototype's resting phase.
    public static let resting = 0.3

    public private(set) var phase: Double
    public private(set) var anchor: Date
    public private(set) var isRunning: Bool

    public init(phase: Double = HorizonBandPhase.resting, anchor: Date, isRunning: Bool) {
        self.phase = Self.wrapped(phase)
        self.anchor = anchor
        self.isRunning = isRunning
    }

    /// Whether the bands move: only while the day runs and Reduce Motion is off.
    public static func isRunning(dayIsRunning: Bool, reduceMotion: Bool) -> Bool {
        dayIsRunning && !reduceMotion
    }

    /// The phase at `date`, wrapped to one band (a whole band of phase draws
    /// the same sky), which keeps the shader's float precision.
    public func value(at date: Date) -> Double {
        guard isRunning else { return phase }
        let elapsed = max(0, date.timeIntervalSince(anchor))
        return Self.wrapped(phase + elapsed * Self.bandsPerSecond)
    }

    /// Re-anchors at `date` with a new running state, keeping the value.
    public func updating(isRunning running: Bool, at date: Date) -> HorizonBandPhase {
        HorizonBandPhase(phase: value(at: date), anchor: date, isRunning: running)
    }

    private static func wrapped(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }
}
