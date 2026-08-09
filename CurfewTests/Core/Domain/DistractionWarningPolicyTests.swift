@testable import Curfew
import Foundation
import Testing

/// `DistractionWarningPolicy`, hold reasons and all.
///
/// Every `hold` case gets its own test because the silences are the product
/// decisions: a nudge fired at an empty chair, during a lockout, or every
/// three minutes for an hour would each be a worse outcome than not shipping
/// the nudge at all.
struct DistractionWarningPolicyTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let policy = DistractionWarningPolicy.default

    private func decide(
        state: PresenceState = .presentButIdle,
        phase: EnforcementPhase = .working,
        secondsInState: TimeInterval = 600,
        secondsSinceLastWarning: TimeInterval = .greatestFiniteMagnitude,
        isEnabled: Bool = true
    ) -> DistractionWarningPolicy.Verdict {
        let lastWarnedAt = secondsSinceLastWarning == .greatestFiniteMagnitude
            ? Date.distantPast
            : epoch.addingTimeInterval(-secondsSinceLastWarning)
        return policy.decide(
            state: state,
            phase: phase,
            stateEnteredAt: epoch.addingTimeInterval(-secondsInState),
            lastWarnedAt: lastWarnedAt,
            now: epoch,
            isEnabled: isEnabled
        )
    }

    @Test("A sustained present-but-idle stretch during work hours earns a nudge")
    func sustainedDistractionWarns() {
        #expect(decide() == .warn)
    }

    @Test("Nudges are held while the feature is off")
    func disabledHolds() {
        #expect(decide(isEnabled: false) == .hold(.disabled))
    }

    @Test("Only present-but-idle counts as distraction")
    func otherStatesHold() {
        // Absent is the important one: nobody is there to read the banner, and
        // firing at an empty chair is how a nudge becomes noise.
        #expect(decide(state: .absent) == .hold(.notDistracted))
        #expect(decide(state: .working) == .hold(.notDistracted))
        // Unknown is the default-install state — the camera is off, so Curfew
        // has no basis for calling anyone distracted.
        #expect(decide(state: .unknown) == .hold(.notDistracted))
    }

    @Test("No nudge during lockout or on a day off")
    func ineligiblePhasesHold() {
        let locked = EnforcementPhase.locked
        #expect(decide(phase: locked) == .hold(.phaseNotEligible))
        #expect(decide(phase: .dayOff) == .hold(.phaseNotEligible))
        #expect(!DistractionWarningPolicy.isEligible(locked))
        #expect(!DistractionWarningPolicy.isEligible(.dayOff))
    }

    @Test("The warning run-up to curfew is still eligible")
    func warningPhaseIsEligible() {
        #expect(decide(phase: .warning) == .warn)
        #expect(DistractionWarningPolicy.isEligible(.warning))
    }

    @Test("A brief pause is not a distraction")
    func briefPauseHolds() {
        #expect(decide(secondsInState: 30) == .hold(.tooBrief))
        #expect(decide(secondsInState: 179) == .hold(.tooBrief))
        #expect(decide(secondsInState: 180) == .warn)
    }

    @Test("A second nudge waits out the repeat window")
    func repeatWindowHolds() {
        #expect(decide(secondsSinceLastWarning: 60) == .hold(.recentlyWarned))
        #expect(decide(secondsSinceLastWarning: 599) == .hold(.recentlyWarned))
        #expect(decide(secondsSinceLastWarning: 600) == .warn)
    }

    @Test("Absurd windows are clamped rather than honoured")
    func windowsAreClamped() {
        // A zero sustained window would fire the instant the user looked away;
        // a day-long one would mean the feature silently never fires. Both are
        // pulled back into the supported range.
        let tooSmall = DistractionWarningPolicy(sustainedSeconds: 0, repeatSeconds: 0)
        #expect(
            tooSmall.sustainedSeconds
                == TimeInterval(DistractionWarningPolicy.sustainedFloorSeconds)
        )
        #expect(
            tooSmall.repeatSeconds
                == TimeInterval(DistractionWarningPolicy.repeatFloorSeconds)
        )

        let tooLarge = DistractionWarningPolicy(
            sustainedSeconds: 999_999,
            repeatSeconds: 999_999
        )
        #expect(
            tooLarge.sustainedSeconds
                == TimeInterval(DistractionWarningPolicy.sustainedCeilingSeconds)
        )
        #expect(
            tooLarge.repeatSeconds
                == TimeInterval(DistractionWarningPolicy.repeatCeilingSeconds)
        )
    }

    @Test("The disabled check runs before every other, so an off switch is absolute")
    func disabledOutranksEverything() {
        // Even a state that would otherwise warn on every axis stays silent.
        #expect(
            decide(
                state: .presentButIdle,
                phase: .working,
                secondsInState: 100_000,
                isEnabled: false
            ) == .hold(.disabled)
        )
    }
}

/// The presence settings themselves — the defaults and the upgrade path.
///
/// These assert the single most important fact about the whole feature: it is
/// off, and nothing short of a person turning it on changes that.
struct PresenceDetectionPolicyTests {
    @Test("Presence detection ships with the camera off")
    func cameraIsOffByDefault() {
        #expect(!PresenceDetectionPolicy.default.cameraEnabled)
        #expect(!CurfewSettings.default.presence.cameraEnabled)
    }

    @Test("Settings written before presence existed decode with the camera off")
    func legacySettingsDecodeWithCameraOff() throws {
        // A payload from a build that had never heard of `presence`. The
        // upgrade must land on "off", not on "whatever the decoder felt like".
        var legacy = CurfewSettings.default
        legacy.hasCompletedInitialSetup = true
        let encoded = try JSONEncoder().encode(legacy)
        let json = try JSONSerialization.jsonObject(with: encoded)
        var object = try #require(json as? [String: Any])
        object.removeValue(forKey: "presence")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CurfewSettings.self, from: stripped)

        #expect(!decoded.presence.cameraEnabled)
        #expect(decoded.presence == .default)
    }

    @Test("A partial presence payload still decodes with the camera off")
    func partialPayloadDecodesWithCameraOff() throws {
        let json = Data(#"{"warnsWhenDistracted":false}"#.utf8)
        let decoded = try JSONDecoder().decode(PresenceDetectionPolicy.self, from: json)
        #expect(!decoded.cameraEnabled)
        #expect(!decoded.warnsWhenDistracted)
        #expect(
            decoded.distractionSustainedSeconds
                == PresenceDetectionPolicy.default.distractionSustainedSeconds
        )
    }

    @Test("Presence settings round-trip through the store")
    func presenceRoundTrips() throws {
        var settings = CurfewSettings.default
        settings.presence.cameraEnabled = true
        settings.presence.distractionSustainedSeconds = 300

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CurfewSettings.self, from: data)

        #expect(decoded.presence.cameraEnabled)
        #expect(decoded.presence.distractionSustainedSeconds == 300)
    }

    @Test("The derived nudge policy clamps whatever the settings hold")
    func derivedPolicyIsClamped() {
        var settings = PresenceDetectionPolicy.default
        settings.distractionSustainedSeconds = 1
        settings.distractionRepeatSeconds = 1
        let policy = settings.distractionPolicy
        #expect(
            policy.sustainedSeconds
                == TimeInterval(DistractionWarningPolicy.sustainedFloorSeconds)
        )
        #expect(
            policy.repeatSeconds
                == TimeInterval(DistractionWarningPolicy.repeatFloorSeconds)
        )
    }
}
