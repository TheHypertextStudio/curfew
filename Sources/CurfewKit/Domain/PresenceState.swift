import Foundation

/// What the camera last said about whether a person is in front of the Mac.
///
/// Three cases rather than a `Bool?` because "the camera is not running" is a
/// real, common, and *default* state — presence detection ships off — and it
/// means something different from "the camera looked and saw nobody". Folding
/// the two together would let a disabled camera read as an empty chair, which
/// is the one mistake this signal must never make.
///
/// The signal says *a* person, never *which* person. Curfew runs
/// `VNDetectHumanRectanglesRequest`, which returns bounding boxes; it does not
/// run face identification, does not build a template, and has nothing to
/// compare a face against. See `Documentation/presence-detection.md`.
public enum PersonSignal: String, Codable, Equatable, CaseIterable, Sendable {
    /// The most recent analysed frame contained at least one human figure.
    case detected

    /// The most recent analysed frame contained no human figure.
    case notDetected = "not_detected"

    /// There is no usable camera signal right now: detection is switched off,
    /// camera access was never granted or was revoked, the machine has no
    /// capture device, or the last observation is older than the monitor's
    /// tolerance. Never means "nobody is there".
    case unavailable
}

/// Curfew's fused answer to "is the human actually at this machine, working?"
///
/// Neither input can answer it alone. HID idleness knows when the keyboard and
/// trackpad went quiet but cannot tell reading from an empty room, and the
/// camera knows a body is in frame but not whether that body is doing anything.
/// Crossing them separates the three cases the product actually cares about,
/// plus an honest fourth for when it cannot tell.
public enum PresenceState: String, Codable, Equatable, CaseIterable, Sendable {
    /// Input arrived inside the idle threshold. Somebody is here and using the
    /// Mac; this is the state work time accrues in.
    case working

    /// No input for longer than the idle threshold, but the camera sees a
    /// person. Reading, thinking, on a call, or staring out of the window —
    /// present, not working. The only state a distraction nudge is aimed at.
    case presentButIdle = "present_idle"

    /// No input for longer than the idle threshold and the camera sees nobody.
    /// The user walked away.
    case absent

    /// No input for longer than the idle threshold and no camera signal to
    /// disambiguate. Curfew knows the machine is quiet and refuses to guess
    /// why. This is the steady state on a default install, where camera
    /// presence detection is off.
    case unknown

    /// Whether a person is known to be at the machine. `false` for
    /// ``unknown`` — absence of evidence is not evidence of presence.
    public var isPersonKnownPresent: Bool {
        self == .working || self == .presentButIdle
    }

    /// Whether Curfew is confident nobody is at the machine. `true` only for
    /// ``absent``, which requires a positive "camera looked and saw nobody".
    public var isPersonKnownAbsent: Bool {
        self == .absent
    }
}

/// Crosses the HID idle signal with the camera person signal.
///
/// A free function in an enum namespace rather than a method on anything
/// stateful, because this is the whole of the fusion rule and it should be
/// readable — and testable — without constructing a capture session.
public enum PresenceFusion {
    /// Resolves the fused presence state.
    ///
    /// **HID activity wins outright.** If input arrived recently the answer is
    /// ``PresenceState/working`` no matter what the camera says, because a
    /// person typing on an external keyboard, sitting outside the lens' cone,
    /// or working in a dark room is still working — and a camera that
    /// contradicts live keystrokes is wrong about the room, not about the
    /// user. The cost of that rule is that Curfew cannot distinguish a human
    /// from a mouse jiggler, which is a trade the product accepts: Curfew is a
    /// commitment device for its own user, not an invigilator.
    ///
    /// - Parameters:
    ///   - isHIDIdle: Whether `IdleWatcher` reports the user idle — no
    ///     keyboard, mouse, or trackpad event for longer than its threshold.
    ///   - person: The camera's most recent verdict, or
    ///     ``PersonSignal/unavailable`` when there isn't one.
    /// - Returns: The fused state.
    public static func resolve(isHIDIdle: Bool, person: PersonSignal) -> PresenceState {
        guard isHIDIdle else {
            return .working
        }
        switch person {
        case .detected: return .presentButIdle
        case .notDetected: return .absent
        case .unavailable: return .unknown
        }
    }
}

/// One reading from a person-presence sensor, with the moment it was taken.
///
/// The timestamp is what lets a consumer distinguish "the camera says nobody
/// is here" from "the camera said nobody was here four minutes ago and has not
/// produced a frame since". A wedged capture session must decay to
/// ``PersonSignal/unavailable`` rather than pin a stale verdict forever.
///
/// A struct with a sentinel rather than an optional: ``never`` is the
/// well-defined "no reading yet" value, and it is already older than any
/// tolerance a caller could configure, so the staleness check handles the
/// never-observed case with no extra branch.
/// `nonisolated` as a whole type because the app target compiles with
/// `-default-isolation=MainActor`, which would otherwise bind this value's
/// initialiser and constants to the main actor — and the code that produces
/// observations, ``CameraPresenceEngine``, runs on its own queue by design.
/// Safe because every stored property is an immutable-in-practice `Sendable`
/// value.
public nonisolated struct PersonObservation: Equatable, Sendable {
    /// What the sensor saw.
    public var signal: PersonSignal

    /// When it saw it. ``Date/distantPast`` when nothing has been observed.
    public var timestamp: Date

    /// Creates an observation.
    public init(signal: PersonSignal, timestamp: Date) {
        self.signal = signal
        self.timestamp = timestamp
    }

    /// The "nothing observed yet" reading. Its timestamp is far enough in the
    /// past that every staleness check rejects it.
    public static let never = PersonObservation(
        signal: .unavailable,
        timestamp: .distantPast
    )

    /// Whether this reading is still trustworthy at `now`.
    ///
    /// - Parameters:
    ///   - now: The moment to judge freshness against.
    ///   - tolerance: How old a reading may be and still count.
    /// - Returns: `false` for ``never`` and for anything older than
    ///   `tolerance`, including a reading with a timestamp in the future
    ///   (a clock step backwards, which must not extend a reading's life).
    public func isFresh(at now: Date, tolerance: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age >= 0 && age <= tolerance
    }

    /// The signal if it is still fresh, otherwise ``PersonSignal/unavailable``.
    public func signal(at now: Date, tolerance: TimeInterval) -> PersonSignal {
        isFresh(at: now, tolerance: tolerance) ? signal : .unavailable
    }
}

/// Whether the user has granted Curfew camera access, mirrored off
/// `AVAuthorizationStatus` so the domain layer carries no AVFoundation import
/// and tests can drive every branch without touching TCC.
public enum CameraAuthorization: String, Codable, Equatable, CaseIterable, Sendable {
    /// The user has never been asked. Curfew asks only when the user turns
    /// presence detection on — never at launch, never speculatively.
    case notDetermined = "not_determined"

    /// The user said no, or revoked access later.
    case denied

    /// Camera access is barred by policy (Screen Time, MDM). Not the user's
    /// choice and not something Curfew can prompt its way out of.
    case restricted

    /// Access granted. The only value that permits a capture session to start.
    case authorized

    /// Whether a capture session may run. `true` only for ``authorized``.
    public var permitsCapture: Bool {
        self == .authorized
    }

    /// Whether asking would surface a system prompt. Only ``notDetermined``
    /// produces a dialog; the other cases need a trip to System Settings.
    public var canPrompt: Bool {
        self == .notDetermined
    }
}
