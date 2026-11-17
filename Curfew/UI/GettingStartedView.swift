import AppKit
import CurfewKit
import SwiftUI

/// First-run setup, hosted by the `getting-started` window.
///
/// Three steps and one optional closing step:
/// 1. When should this Mac close for the night? (an explicit schedule choice)
/// 2. Let Curfew hold the lock. (Accessibility, required; notifications and
///    the Curfew helper, optional) Setup commits the moment access is granted.
/// 3. You're set. States tonight's curfew and previews the lock.
/// Then sync and the lifetime licence, which can be skipped as easily.
///
/// Progress is saved on every step change so setup reopens where the person
/// left it until it is completed.
struct GettingStartedView: View {
    @Environment(CurfewAppModel.self) private var model

    @State private var flow: FirstRunFlow
    @State private var hasLoaded: Bool
    @State private var draft: SetupScheduleDraft?
    @State private var notificationStatus: SetupPermissionStatus
    @State private var dragHelper: AccessibilityDragHelper?
    @State private var preview: LockPreviewController?
    @State private var confirmingImmediateLock = false
    @State private var signedIn = false
    @State private var notificationsSkipped = false
    @State private var helperSkipped = false
    @FocusState private var continueFocused: Bool
    @AccessibilityFocusState private var headingFocused: Bool

    /// `nil` uses the system; fixed values serve snapshots.
    private let notifications: (any NotificationPermissionProviding)?
    /// `nil` uses the app's account enrollment, the same one Settings uses.
    private let makeAccount: (@MainActor () -> AccountEnrollmentController)?
    private let now: () -> Date

    /// - Parameters:
    ///   - flow: A fixed cursor for snapshots; `nil` loads saved progress.
    ///   - notifications: Reads and requests notification permission.
    ///   - notificationStatus: The status shown before the first read.
    init(
        flow: FirstRunFlow? = nil,
        notifications: (any NotificationPermissionProviding)? = nil,
        notificationStatus: SetupPermissionStatus = .notAsked,
        makeAccount: (@MainActor () -> AccountEnrollmentController)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.makeAccount = makeAccount
        _flow = State(initialValue: flow ?? FirstRunFlow())
        _hasLoaded = State(initialValue: flow != nil)
        _notificationStatus = State(initialValue: notificationStatus)
        self.notifications = notifications
        self.now = now
    }

    var body: some View {
        ZStack {
            GettingStartedBackdrop()
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: GettingStartedLayout.spacing24) {
                        header
                        stepContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, GettingStartedLayout.spacing40)
                    .padding(.top, GettingStartedLayout.spacing40)
                    .padding(.bottom, GettingStartedLayout.spacing24)
                }
                .scrollBounceBehavior(.basedOnSize)
                actionRow
                    .padding(.horizontal, GettingStartedLayout.spacing40)
                    .padding(.bottom, GettingStartedLayout.spacing24)
            }
        }
        .frame(
            minWidth: GettingStartedLayout.contentMinimum.width,
            idealWidth: GettingStartedLayout.windowSize.width,
            minHeight: GettingStartedLayout.contentMinimum.height,
            idealHeight: GettingStartedLayout.windowSize.height
        )
        .foregroundStyle(CurfewTheme.ink)
        .tint(CurfewTheme.accent)
        .onAppear(perform: load)
        .onDisappear {
            dragHelper?.stop()
            preview?.dismiss()
        }
        .onChange(of: flow.currentStep) { _, step in stepChanged(to: step) }
        .onChange(of: optionalsResolved) { _, resolved in
            flow.updateOptionalPermissions(resolved: resolved)
        }
        .onChange(of: model.isAccessibilityTrusted) { _, trusted in
            flow.updateAccessibilityGranted(trusted)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            refreshPermissions()
        }
        .alert(GettingStartedCopy.immediateLockTitle, isPresented: $confirmingImmediateLock) {
            Button(GettingStartedCopy.immediateLockConfirm, role: .destructive) {
                continueFromPermissions(confirmedImmediateLock: true)
            }
            Button(GettingStartedCopy.immediateLockCancel, role: .cancel) {
                flow.retreat()
            }
        } message: {
            Text(GettingStartedCopy.immediateLockMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: GettingStartedLayout.spacing8) {
            if !flow.isReview {
                Text(flow.currentStep.progressLabel)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
            Text(flow.currentStep.title)
                .font(.setupHeading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.currentStep {
        case .schedule:
            GettingStartedScheduleStep(draft: draftBinding)
        case .permissions:
            GettingStartedPermissionsStep(
                notificationStatus: notificationStatus,
                helperStatus: helperStatus,
                showsHelper: model.featureFlags.privilegedHelperEnabled,
                accessibilityGranted: model.isAccessibilityTrusted,
                notificationsSkipped: notificationsSkipped,
                helperSkipped: helperSkipped,
                onSkipNotifications: { notificationsSkipped = true },
                onSkipHelper: { helperSkipped = true },
                onAllowNotifications: requestNotifications,
                onInstallHelper: installHelper,
                onApproveHelper: approveHelper,
                onOpenAccessibility: openAccessibility
            )
        case .ready:
            GettingStartedReadyStep(
                readyLine: GettingStartedCopy.readyLine(
                    curfew: model.nextCurfew(after: now(), usesWeeklySchedule: usesWeeklySchedule),
                    now: now()
                ),
                helperNote: model.helperAbsenceNote,
                onPreview: previewLock
            )
        case .extras:
            GettingStartedExtrasStep(
                makeAccount: makeAccount ?? { AccountEnrollmentController.settingsController() },
                onSignedIn: { signedIn = true }
            )
        }
    }

    private var actionRow: some View {
        HStack(spacing: GettingStartedLayout.spacing12) {
            switch flow.currentStep {
            case .schedule:
                Button(GettingStartedCopy.noScheduleYet) {
                    flow.chooseSchedule(.remoteControlsOnly)
                }
                .buttonStyle(GettingStartedLinkButtonStyle())
                .help(GettingStartedCopy.noScheduleYetHint)
                .accessibilityHint(GettingStartedCopy.noScheduleYetHint)
                Spacer()
                Button(GettingStartedCopy.useSchedule) {
                    if let draft {
                        model.applySetupSchedule(draft)
                    }
                    flow.chooseSchedule(.weeklySchedule)
                }
                .buttonStyle(GettingStartedPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(draft?.workingDays.isEmpty ?? true)
            case .permissions:
                if flow.canGoBack {
                    Button("Back") { flow.retreat() }
                        .buttonStyle(GettingStartedSecondaryButtonStyle())
                }
                Spacer()
                Button(flow.isReview ? "Done" : "Continue") {
                    continueFromPermissions()
                }
                .buttonStyle(GettingStartedPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .focused($continueFocused)
                .disabled(!flow.canAdvance)
            case .ready:
                Spacer()
                if flow.isReview {
                    Button("Done") { model.dismissGettingStarted() }
                        .buttonStyle(GettingStartedPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { flow.advance() }
                        .buttonStyle(GettingStartedPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            case .extras:
                Spacer()
                Button(signedIn ? "Done" : "Skip") { model.finishGettingStarted() }
                    .buttonStyle(GettingStartedSecondaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private extension GettingStartedView {
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

    func load() {
        if !hasLoaded {
            hasLoaded = true
            flow = model.loadSetupFlow()
        }
        if draft == nil {
            draft = model.setupScheduleDraft
        }
        if !model.isDemoSession {
            model.refreshAccessibilityTrust()
            model.privilegedHelperManager.refreshStatus()
        }
        flow.updateOptionalPermissions(resolved: optionalsResolved)
        flow.updateAccessibilityGranted(model.isAccessibilityTrusted)
        refreshPermissions()
        stepChanged(to: flow.currentStep, announce: false)
    }

    func stepChanged(to step: FirstRunStep, announce: Bool = true) {
        model.saveSetupProgress(flow)
        headingFocused = true
        if announce {
            let prefix = flow.isReview ? "" : "\(step.progressLabel). "
            AccessibilityNotification.Announcement("\(prefix)\(step.title)").post()
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
            flow.updateOptionalPermissions(resolved: optionalsResolved)
            flow.updateAccessibilityGranted(true)
            holdOrContinueAfterGrant()
        }
        dragHelper = helper
        return helper
    }

    func openAccessibility() {
        guard !model.isDemoSession else { return }
        accessibilityHelper().openSystemSettings()
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

    /// Notifications are resolved once allowed, turned off or skipped; the
    /// helper once installed, awaiting approval, skipped, or not offered.
    var optionalsResolved: Bool {
        let notifications = notificationStatus != .notAsked || notificationsSkipped
        let helper = !model.featureFlags.privilegedHelperEnabled || helperSkipped
            || helperStatus == .installed || helperStatus == .needsApproval
        return notifications && helper
    }

    /// A fresh grant advances only when both optional rows are resolved;
    /// otherwise setup comes forward on step 2 with Continue focused.
    func holdOrContinueAfterGrant() {
        model.appRouter.activate()
        if flow.optionalsResolved {
            continueFromPermissions()
        } else {
            AccessibilityNotification.Announcement("Accessibility allowed.").post()
            continueFocused = true
        }
    }

    /// Commits setup once access is granted. A schedule that would lock
    /// right away asks first, in plain words.
    func continueFromPermissions(confirmedImmediateLock: Bool = false) {
        guard flow.isAccessibilityGranted, flow.currentStep == .permissions else { return }
        switch model.commitSetup(flow, confirmedImmediateLock: confirmedImmediateLock) {
        case .activated:
            dragHelper?.stop()
            flow.markCommitted()
            model.appRouter.activate()
        case .requiresImmediateLockConfirmation:
            model.appRouter.activate()
            confirmingImmediateLock = true
        case .unavailable:
            break
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
