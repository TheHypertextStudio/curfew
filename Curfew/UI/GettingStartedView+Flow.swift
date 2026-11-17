import AppKit
import CurfewKit
import SwiftUI

// MARK: Loading, permissions and commit

extension GettingStartedView {
    var notificationProvider: any NotificationPermissionProviding {
        notifications ?? SystemNotificationPermission()
    }

    var usesWeeklySchedule: Bool {
        flow.isReview ? model.automaticScheduleEnabled : flow.usesWeeklySchedule
    }

    var draftBinding: Binding<SetupScheduleDraft> {
        Binding(
            get: { draft ?? model.setupScheduleDraft },
            set: { draft = $0 }
        )
    }

    var helperStatus: SetupHelperStatus {
        let helper = model.privilegedHelperManager
        return SetupHelperStatus.resolve(
            daemon: helper.daemonStatus,
            connection: helper.connectionState,
            isInstalling: helper.installationInProgress
        )
    }

    func stepChanged(to step: FirstRunStep, announce: Bool = true) {
        model.saveSetupProgress(flow)
        if announce {
            AccessibilityNotification.Announcement(step.title).post()
        }
        if step == .permissions, !flow.isCommitted || flow.isReview {
            accessibilityHelper().startPolling()
        } else {
            dragHelper?.stop()
        }
    }

    func refreshPermissions() {
        let provider = notificationProvider
        Task { notificationStatus = await provider.status() }
    }

    func accessibilityHelper() -> AccessibilityDragHelper {
        if let dragHelper {
            return dragHelper
        }
        let model = model
        let helper = AccessibilityDragHelper(
            isTrusted: {
                if !model.isDemoSession {
                    model.refreshAccessibilityTrust()
                }
                return model.isAccessibilityTrusted
            },
            windows: SystemSettingsWindowLocator(),
            screens: { NSScreen.screens.map(\.visibleFrame) },
            presenter: DragPanelWindowPresenter(),
            openPane: { model.openAccessibilityPaneForSetup() }
        )
        helper.onGranted = {
            flow.updateAccessibilityGranted(true)
            continueAfterGrant()
        }
        dragHelper = helper
        return helper
    }

    func openAccessibility() {
        guard !model.isDemoSession else { return }
        accessibilityHelper().openSystemSettings()
        waitingForAccess = true
    }

    func requestNotifications() {
        let provider = notificationProvider
        Task { notificationStatus = await provider.request() }
    }

    func installHelper() {
        Task { await model.privilegedHelperManager.installAndConnectDaemon() }
    }

    func approveHelper() {
        guard !model.isDemoSession else { return }
        model.openHelperApprovalSettings()
    }

    /// A fresh grant brings setup forward and moves it on by itself.
    func continueAfterGrant() {
        model.appRouter.activate()
        waitingForAccess = false
        AccessibilityNotification.Announcement("Accessibility allowed.").post()
        continueFromPermissions(showsGrant: true)
    }

    /// Commits setup once access is granted. A schedule that would lock
    /// right away asks first, in plain words.
    func continueFromPermissions(confirmedImmediateLock: Bool = false, showsGrant: Bool = false) {
        guard flow.isAccessibilityGranted, flow.currentStep == .permissions else { return }
        switch model.commitSetup(flow, confirmedImmediateLock: confirmedImmediateLock) {
        case .activated:
            dragHelper?.stop()
            waitingForAccess = false
            model.appRouter.activate()
            moveOnAfterCommit(showsGrant: showsGrant)
        case .requiresImmediateLockConfirmation:
            model.appRouter.activate()
            confirmingImmediateLock = true
        case .unavailable:
            break
        }
    }

    /// Setup is already committed. After a fresh grant the screen holds on
    /// "Allowed" for a moment before the next one arrives.
    func moveOnAfterCommit(showsGrant: Bool) {
        let asks = SetupOptionalAsk.offered(
            notifications: notificationStatus,
            helper: helperStatus,
            showsHelper: model.featureFlags.privilegedHelperEnabled
        )
        let advance = {
            optionalAsks = asks
            movingOn = false
            change { flow.markCommitted(offersOptional: !asks.isEmpty) }
        }
        guard showsGrant, animates else {
            advance()
            return
        }
        movingOn = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            advance()
        }
    }

    func previewLock() {
        let model = model
        let controller = preview ?? LockPreviewController(
            presenter: LockPreviewWindowPresenter(appearance: { model.restAppearance })
        )
        preview = controller
        controller.present(model.lockPreviewContent(
            now: now(),
            usesWeeklySchedule: usesWeeklySchedule
        ))
    }
}
