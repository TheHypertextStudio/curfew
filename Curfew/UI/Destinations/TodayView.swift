import AppKit
import CurfewKit
import SwiftUI

/// "Today" workspace destination — the live status surface.
///
/// A thin adapter: reads the model's snapshot/state and renders the
/// presentational ``TodaySundownView``. Tonight's curfew window (countdown +
/// lock/unlock) and the on/off control; the weekly retrospective lives in the
/// Journal.
struct TodayView: View {
    @Environment(CurfewAppModel.self) private var model
    /// Binding to the sidebar selection so the empty-state note can navigate
    /// the user directly to the Schedule destination.
    @Binding var selectedSection: MainWorkspaceSection

    var body: some View {
        let snapshot = model.snapshot
        let needsSetup = !model.settings.hasCompletedInitialSetup
        let isLocked = model.state.phase == .locked
        let control = Self.control(needsSetup: needsSetup, enforcing: model.isEnforcementRunning)
        // A countdown exists only when the engine is counting down to a lock —
        // `.locked` and `.dayOff` both report "—", so gate on a real window.
        let hasWindow = model.state.lockDate != nil && snapshot.timeRemainingText != "—"

        TodaySundownView(
            moment: model.skyMoment,
            greeting: Self.greeting(at: model.currentTime),
            timeRemaining: hasWindow ? snapshot.timeRemainingText : "",
            emptyNote: Self.emptyNote(
                needsSetup: needsSetup,
                isLocked: isLocked,
                unlockTime: Self.timeString(model.state.unlockDate)
            ),
            // During an active curfew window the note states status, so it must
            // not double as a "go edit your schedule" button.
            emptyNoteActionable: !isLocked,
            lockTime: Self.timeString(model.state.lockDate),
            unlockTime: Self.timeString(model.state.unlockDate),
            statusLine: control.line,
            statusDetail: control.detail,
            isEnforcing: model.isEnforcementRunning,
            showAccessibilityWarning: !model.isAccessibilityTrusted,
            showAccessibilityGranted: model.accessibilityJustGranted,
            streak: model.thisWeekRollup().streak,
            primaryActionLabel: control.action,
            onPrimaryAction: {
                if needsSetup {
                    model.completeInitialSetup()
                } else {
                    model.start()
                }
            },
            onEmptyNoteAction: { selectedSection = .schedule },
            onResolveAccessibility: { model.requestAccessibilityAccess() }
        )
    }

    /// Hero copy for the no-countdown states. Distinguishes an active curfew
    /// (`.locked` → state the window, not "nothing scheduled") from a genuine
    /// day off and from first-run setup.
    private static func emptyNote(needsSetup: Bool, isLocked: Bool, unlockTime: String) -> String {
        if needsSetup {
            return "Set your schedule to begin."
        }
        if isLocked {
            return unlockTime == "—"
                ? "Curfew is active."
                : "Curfew is active until \(unlockTime)."
        }
        return "No curfew scheduled today."
    }

    /// The bottom-section copy + action for the current state.
    private struct Control {
        let line: String
        let detail: String
        let action: String
    }

    private static func control(needsSetup: Bool, enforcing: Bool) -> Control {
        if needsSetup {
            return Control(
                line: "Finish setting up Curfew",
                detail: "Set your schedule, then turn Curfew on.",
                action: "Finish Setup"
            )
        }
        if enforcing {
            return Control(
                line: "Curfew is on",
                detail: "It's holding your schedule tonight.",
                action: ""
            )
        }
        return Control(
            line: "Curfew is off",
            detail: "Your Mac won't lock tonight until you turn it on.",
            action: "Turn on Curfew"
        )
    }

    private static func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5 ..< 12: "Good morning"
        case 12 ..< 17: "Good afternoon"
        case 17 ..< 24: "Good evening"
        default: "Still up?" // midnight through 4 AM
        }
    }

    private static func timeString(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
