@testable import Curfew
import Foundation
import Testing

/// When the distraction nudge is allowed to speak, driven through the live
/// model.
///
/// Every test here is a restraint: the nudge stays quiet for a brief pause, for
/// a repeat inside the hold window, during lockout, and when the user turned it
/// off. Only one of them asserts that a nudge fires at all. That ratio is the
/// point — a nudge that fires when it should not is the failure mode that makes
/// people turn the feature off.
///
/// The gate and the audit records share this wiring but answer a different
/// question, and live in `PresenceAuditWiringTests`.
@MainActor
struct PresenceNudgeWiringTests {
    @Test("A freshly begun pause does not produce a nudge")
    func briefPauseStaysSilent() {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let harness = PresenceWiringHarness(presence: presence)
        let model = harness.model

        // The stretch starts now, so it is seconds old at most — well inside
        // the sustained window. Standing up to stretch is not a distraction.
        harness.backdatePresentButIdle(secondsAgo: 0)

        model.state = PresenceWiringHarness.workingEvaluation
        model.evaluateDistractionWarning()

        #expect(model.presenceState == .presentButIdle)
        #expect(harness.writer.records(ofType: .presenceDistractionWarned).isEmpty)
    }

    @Test("A sustained distraction is nudged once, then held for the repeat window")
    func sustainedDistractionIsNudgedOnce() throws {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let harness = PresenceWiringHarness(presence: presence)
        let model = harness.model

        harness.backdatePresentButIdle(secondsAgo: 1800)
        #expect(model.presenceState == .presentButIdle)

        model.state = PresenceWiringHarness.workingEvaluation

        model.evaluateDistractionWarning()
        let warnings = harness.writer.records(ofType: .presenceDistractionWarned)
        #expect(warnings.count == 1)
        let record = try #require(warnings.first)
        #expect(record.actor.token == "app")
        #expect(harness.detailString(record, "state") == "present_idle")
        #expect(harness.detailString(record, "phase") == "working")

        // Immediately again: the repeat window has not elapsed, so nothing
        // more is written. This is what stops a long meeting from producing a
        // banner every second.
        model.evaluateDistractionWarning()
        #expect(harness.writer.records(ofType: .presenceDistractionWarned).count == 1)
    }

    @Test("No nudge during lockout, however long the user has been still")
    func noNudgeDuringLockout() {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let harness = PresenceWiringHarness(presence: presence)

        let past = harness.backdatePresentButIdle(secondsAgo: 1800)

        harness.model.state = .locked(
            lockDate: past,
            unlockDate: Date().addingTimeInterval(3600)
        )
        harness.model.evaluateDistractionWarning()

        // The screen is already covering the Mac; "get back to work" is the
        // opposite of what Curfew is saying at that moment.
        #expect(harness.writer.records(ofType: .presenceDistractionWarned).isEmpty)
    }

    @Test("No nudge when the user turned nudges off but kept presence detection on")
    func nudgeSwitchIsIndependent() {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        presence.warnsWhenDistracted = false
        let harness = PresenceWiringHarness(presence: presence)
        let model = harness.model

        harness.backdatePresentButIdle(secondsAgo: 1800)

        model.state = PresenceWiringHarness.workingEvaluation
        model.evaluateDistractionWarning()

        #expect(model.presenceState == .presentButIdle)
        #expect(harness.writer.records(ofType: .presenceDistractionWarned).isEmpty)
    }

    @Test("No nudge fires while presence detection is off")
    func noNudgeWithoutTheCamera() {
        let harness = PresenceWiringHarness()

        for _ in 0 ..< 10 {
            harness.model.tick()
        }

        #expect(harness.writer.records(ofType: .presenceDistractionWarned).isEmpty)
        #expect(harness.model.presenceState == .unknown)
    }
}
