import Foundation

/// User settings for camera-based presence detection.
///
/// The important line in this file is ``default``: `cameraEnabled` is `false`.
/// A fresh install, a restored backup, a settings blob written by an older
/// build that had never heard of this struct, and a corrupted preferences file
/// all resolve to a camera that does not turn on. Every decode path below
/// falls back to ``default`` for the same reason.
///
/// Nothing here is a switch an AI assistant or the CLI can flip: the MCP write
/// tools cover schedule, extensions, and overrides, and turning on a camera is
/// not on that list. Consent for a camera has to come from the person whose
/// camera it is, in Curfew's own Settings window, once.
///
/// What is captured, derived, and retained is written down in
/// `Documentation/presence-detection.md` and summarised in `PRIVACY.md`.
public struct PresenceDetectionPolicy: Codable, Equatable, Sendable {
    /// How stale a camera reading may be before the monitor stops believing
    /// it and falls back to ``PersonSignal/unavailable``.
    ///
    /// Not user-configurable. It exists so a capture session that wedges — the
    /// lid closes, another app seizes the device, the delegate queue stalls —
    /// decays to an honest "no signal" instead of pinning whatever it last saw
    /// and reporting a person who left twenty minutes ago.
    public static let observationToleranceSeconds: TimeInterval = 20

    /// How often the sensor runs a frame through Vision, in seconds.
    ///
    /// Presence changes on the scale of minutes, so analysing more often buys
    /// nothing and costs battery. Frames arriving between analyses are
    /// discarded without being read.
    ///
    /// `nonisolated` because the throttle that reads it lives on
    /// `CameraPresenceEngine`'s private queue, off the main actor, and the app
    /// target compiles with `-default-isolation=MainActor`.
    public nonisolated static let analysisIntervalSeconds: TimeInterval = 2

    /// Whether Curfew may run the camera to detect whether a person is at the
    /// machine. **Off unless the user turned it on**, and the only thing that
    /// permits a capture session to exist.
    public var cameraEnabled: Bool

    /// Whether Curfew nudges the user when they are present but idle.
    ///
    /// Inert while ``cameraEnabled`` is `false`, because without the camera
    /// the fused state is ``PresenceState/unknown`` and the policy holds. It
    /// is a separate switch so a user who wants presence recorded in the
    /// retrospective can decline the interruptions.
    public var warnsWhenDistracted: Bool

    /// Seconds of present-but-idle before the first nudge. Clamped to
    /// ``DistractionWarningPolicy/sustainedFloorSeconds`` ...
    /// ``DistractionWarningPolicy/sustainedCeilingSeconds``.
    public var distractionSustainedSeconds: Int

    /// Minimum seconds between nudges during one distraction. Clamped to
    /// ``DistractionWarningPolicy/repeatFloorSeconds`` ...
    /// ``DistractionWarningPolicy/repeatCeilingSeconds``.
    public var distractionRepeatSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case cameraEnabled
        case warnsWhenDistracted
        case distractionSustainedSeconds
        case distractionRepeatSeconds
    }

    /// Memberwise initialiser. Both windows are clamped on assignment so an
    /// out-of-range value written directly to the struct is corrected rather
    /// than persisted.
    public init(
        cameraEnabled: Bool,
        warnsWhenDistracted: Bool,
        distractionSustainedSeconds: Int,
        distractionRepeatSeconds: Int
    ) {
        self.cameraEnabled = cameraEnabled
        self.warnsWhenDistracted = warnsWhenDistracted
        self.distractionSustainedSeconds = distractionSustainedSeconds
        self.distractionRepeatSeconds = distractionRepeatSeconds
    }

    /// Decoder tolerant of a settings payload written before presence
    /// detection existed, which is every payload on every machine that
    /// upgrades into this release.
    ///
    /// `cameraEnabled` decodes with `decodeIfPresent ?? false`, so an upgrade
    /// can only ever land on the camera being off. There is deliberately no
    /// migration that turns it on.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        self.cameraEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .cameraEnabled
        ) ?? fallback.cameraEnabled
        self.warnsWhenDistracted = try container.decodeIfPresent(
            Bool.self,
            forKey: .warnsWhenDistracted
        ) ?? fallback.warnsWhenDistracted
        self.distractionSustainedSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .distractionSustainedSeconds
        ) ?? fallback.distractionSustainedSeconds
        self.distractionRepeatSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .distractionRepeatSeconds
        ) ?? fallback.distractionRepeatSeconds
    }

    /// The nudge cadence these settings describe, with both windows clamped.
    public var distractionPolicy: DistractionWarningPolicy {
        DistractionWarningPolicy(
            sustainedSeconds: distractionSustainedSeconds,
            repeatSeconds: distractionRepeatSeconds
        )
    }

    /// Factory defaults: **camera off**, nudges armed for whenever the user
    /// turns the camera on, three-minute sustained window, ten-minute repeat.
    public static let `default` = PresenceDetectionPolicy(
        cameraEnabled: false,
        warnsWhenDistracted: true,
        distractionSustainedSeconds: 180,
        distractionRepeatSeconds: 600
    )
}
