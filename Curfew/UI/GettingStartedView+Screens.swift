import CurfewKit
import SwiftUI

/// What each screen puts in the scaffold's four places.
extension GettingStartedView {
    var headline: String? {
        switch scene {
        case .welcome:
            switch introPhase {
            case .title, .settled: nil
            case .caption(let index): GettingStartedCopy.introCaptions[index]
            case .rest: GettingStartedCopy.welcomeTitle
            }
        case .schedule: GettingStartedCopy.scheduleTitle
        case .morning: GettingStartedCopy.morningTitle
        case .permissions: FirstRunStep.permissions.title
        case .optional: GettingStartedCopy.optionalTitle(count: optionalAsks.count)
        case .ready: FirstRunStep.ready.title
        case .extras: GettingStartedCopy.extrasTitle
        }
    }

    var wordmark: SetupWordmark {
        guard scene == .welcome else { return .hidden }
        return introPhase == .title ? .title : .mark
    }

    /// The quieter button, to the left of the main one.
    var secondaryAction: SetupAction? {
        switch scene {
        case .welcome:
            if introPhase == .rest {
                SetupAction(title: GettingStartedCopy.watchAgain, perform: playIntro)
            } else {
                SetupAction(title: GettingStartedCopy.skipIntro) { change { flow.begin() } }
            }
        case .schedule:
            SetupAction(
                title: GettingStartedCopy.noScheduleYet,
                hint: GettingStartedCopy.noScheduleYetHint
            ) { change { flow.chooseSchedule(.remoteControlsOnly) } }
        case .permissions:
            if flow.canGoBack {
                SetupAction(title: "Back") { change { flow.retreat() } }
            } else {
                nil
            }
        case .ready:
            SetupAction(
                title: GettingStartedCopy.previewLock,
                hint: "Shows the lock for a few seconds. Nothing locks.",
                perform: previewLock
            )
        case .extras:
            SetupAction(title: signedIn ? "Done" : "Skip") { model.finishGettingStarted() }
        case .morning, .optional:
            nil
        }
    }

    /// The main button. It is in the same place on every screen.
    var primaryAction: SetupAction? {
        switch scene {
        case .welcome:
            if introPhase == .rest {
                SetupAction(title: GettingStartedCopy.begin) { change { flow.begin() } }
            } else {
                nil
            }
        case .schedule:
            SetupAction(
                title: GettingStartedCopy.useSchedule,
                isEnabled: !draftBinding.wrappedValue.workingDays.isEmpty
            ) {
                if let draft {
                    model.applySetupSchedule(draft)
                }
                change { flow.chooseSchedule(.weeklySchedule) }
            }
        case .morning:
            SetupAction(
                title: "Done", isEnabled: !draftBinding.wrappedValue.workingDays.isEmpty
            ) { change { editingMorning = false } }
        case .permissions:
            if flow.isAccessibilityGranted {
                SetupAction(title: flow.isReview ? "Done" : "Continue", isEnabled: !movingOn) {
                    continueFromPermissions()
                }
            } else {
                SetupAction(
                    title: GettingStartedCopy.openSystemSettings,
                    hint: "Opens Accessibility with Curfew ready to drag into the list.",
                    perform: openAccessibility
                )
            }
        case .optional:
            SetupAction(title: "Continue") { change { flow.advance() } }
        case .ready:
            if flow.isReview {
                SetupAction(title: "Done") { model.dismissGettingStarted() }
            } else {
                SetupAction(title: "Continue") { change { flow.advance() } }
            }
        case .extras:
            nil
        }
    }

    @ViewBuilder
    var content: some View {
        switch scene {
        case .welcome:
            GettingStartedWelcomeContent(isRest: introPhase == .rest)
        case .schedule:
            GettingStartedScheduleContent(
                draft: draftBinding, onChange: { change { editingMorning = true } }
            )
        case .morning:
            GettingStartedMorningContent(draft: draftBinding)
        case .permissions:
            GettingStartedPermissionContent(
                granted: flow.isAccessibilityGranted, waiting: waitingForAccess
            )
        case .optional:
            GettingStartedOptionalContent(
                asks: optionalAsks,
                notificationStatus: notificationStatus,
                helperStatus: helperStatus,
                onAllowNotifications: requestNotifications,
                onInstallHelper: installHelper,
                onApproveHelper: approveHelper
            )
        case .ready:
            GettingStartedReadyContent(
                readyLine: GettingStartedCopy.readyLine(
                    curfew: model.nextCurfew(after: now(), usesWeeklySchedule: usesWeeklySchedule),
                    now: now()
                ),
                helperNote: model.helperAbsenceNote
            )
        case .extras:
            GettingStartedExtrasContent(
                makeAccount: makeAccount ?? { AccountEnrollmentController.settingsController() },
                onSignedIn: { signedIn = true }
            )
        }
    }
}
