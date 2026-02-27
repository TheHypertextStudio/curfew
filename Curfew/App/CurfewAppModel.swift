import Foundation
import SwiftUI
import Combine
import AppKit
import CoreGraphics

struct FeatureFlags: Equatable, Sendable {
    var widgetKitEnabled: Bool
    var cloudSyncEnabled: Bool
    var mcpServerEnabled: Bool
    var privilegedHelperEnabled: Bool

    static let `default` = FeatureFlags(
        widgetKitEnabled: false,
        cloudSyncEnabled: false,
        mcpServerEnabled: false,
        privilegedHelperEnabled: false
    )
}

struct EnforcementSnapshot: Equatable, Sendable {
    var phase: EnforcementPhase
    var symbolName: String
    var statusLine: String
    var timeRemainingText: String
    var scheduleWindowText: String
    var scheduleSummarySentence: String
    var pendingScheduleDescription: String?
    var canRequestExtension: Bool
    var extensionRequestTitle: String
    var extensionsRemaining: Int
}

@MainActor
protocol AppRouting: AnyObject {
    func activate()
    func showSettings()
}

@MainActor
final class SystemAppRouter: AppRouting {
    func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

@MainActor
protocol GettingStartedPresenting: AnyObject {
    func present(model: CurfewAppModel)
    func dismiss()
}

@MainActor
final class GettingStartedWindowPresenter: NSObject, GettingStartedPresenting, NSWindowDelegate {
    private var windowController: NSWindowController?

    func present(model: CurfewAppModel) {
        if let window = windowController?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = GettingStartedView().environmentObject(model)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Curfew"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 430))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
    }

    func dismiss() {
        windowController?.close()
        windowController = nil
    }

    func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}

protocol ShutdownControlling: AnyObject {
    func requestGracefulTermination()
    func executeShutdown() -> Bool
}

final class SystemShutdownController: ShutdownControlling {
    func requestGracefulTermination() {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let applications = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier != ownBundleIdentifier
        }
        for application in applications {
            _ = application.terminate()
        }
    }

    func executeShutdown() -> Bool {
        guard let script = NSAppleScript(source: "tell application \"System Events\" to shut down") else {
            return false
        }

        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }
}

struct ShutdownWorkflow: Equatable {
    enum Phase: Equatable {
        case idle
        case scheduled(at: Date)
        case retryScheduled(at: Date)
        case failed
        case completed
    }

    private(set) var phase: Phase = .idle

    mutating func update(
        now: Date,
        isLocked: Bool,
        isEnabled: Bool,
        delayMinutes: Int,
        controller: ShutdownControlling
    ) {
        guard isLocked, isEnabled else {
            phase = .idle
            return
        }

        switch phase {
        case .idle:
            let delay = max(1, delayMinutes)
            phase = .scheduled(at: now.addingTimeInterval(TimeInterval(delay * 60)))
        case let .scheduled(at):
            guard now >= at else {
                return
            }
            controller.requestGracefulTermination()
            if controller.executeShutdown() {
                phase = .completed
            } else {
                phase = .retryScheduled(at: now.addingTimeInterval(60))
            }
        case let .retryScheduled(at):
            guard now >= at else {
                return
            }
            controller.requestGracefulTermination()
            if controller.executeShutdown() {
                phase = .completed
            } else {
                phase = .failed
            }
        case .failed, .completed:
            return
        }
    }

    func statusLine(now: Date) -> String? {
        switch phase {
        case let .scheduled(at):
            let remaining = max(0, Int(at.timeIntervalSince(now)))
            return "Your Mac is going to sleep in \(ShutdownWorkflow.format(seconds: remaining))."
        case let .retryScheduled(at):
            let remaining = max(0, Int(at.timeIntervalSince(now)))
            return "Retrying shutdown in \(ShutdownWorkflow.format(seconds: remaining))."
        case .failed:
            return "Shutdown failed. Lockout remains active."
        case .completed, .idle:
            return nil
        }
    }

    private static func format(seconds: Int) -> String {
        let minutes = seconds / 60
        let secondComponent = seconds % 60
        return String(format: "%d:%02d", minutes, secondComponent)
    }
}

enum LockoutShortcutPolicy {
    static func shouldBlock(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        let command = flags.contains(.maskCommand)
        let option = flags.contains(.maskAlternate)
        let control = flags.contains(.maskControl)

        if command && keyCode == 48 { // tab
            return true
        }
        if command && keyCode == 12 { // q
            return true
        }
        if command && keyCode == 49 { // space
            return true
        }
        if command && option && keyCode == 53 { // escape
            return true
        }
        if control && [123, 124, 125, 126].contains(keyCode) { // arrows
            return true
        }
        return false
    }
}

final class LockoutKeyInterceptor {
    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?

    var isActive: Bool {
        eventTap != nil
    }

    func start() {
        guard eventTap == nil else {
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            guard type == .keyDown || type == .flagsChanged else {
                return Unmanaged.passUnretained(event)
            }

            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags

            if LockoutShortcutPolicy.shouldBlock(keyCode: keyCode, flags: flags) {
                return nil
            }

            return Unmanaged.passUnretained(event)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: nil
            )
        else {
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        source = runLoopSource
    }

    func stop() {
        guard let tap = eventTap, let source else {
            eventTap = nil
            self.source = nil
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = nil
        self.source = nil
    }
}

enum SchedulePreset: String, CaseIterable, Identifiable {
    case nineToFive = "9-to-5"
    case startupHours = "Startup Hours"
    case halfDay = "Half Day"

    var id: String { rawValue }
}

enum EncouragementMessageCatalog {
    static let messages = [
        "Great work today. Tomorrow is another day.",
        "The best code is written by a rested mind.",
        "You've earned this. Go live your life.",
        "Nothing in your inbox is more important than your health.",
        "Future you will be grateful."
    ]

    static func next(after previous: String?) -> String {
        guard let previous, let index = messages.firstIndex(of: previous), !messages.isEmpty else {
            return messages.first ?? "Great work today."
        }
        let nextIndex = (index + 1) % messages.count
        return messages[nextIndex]
    }
}

@MainActor
final class CurfewAppModel: NSObject, ObservableObject {
    static let extensionConfirmationHoldSeconds: Double = 2

    let shouldOpenSettingsOnLaunch: Bool
    let featureFlags: FeatureFlags

    @Published var settings: CurfewSettings {
        didSet {
            handleSettingsMutation(from: oldValue)
        }
    }
    @Published var state: CurfewEvaluation
    @Published var currentTime: Date = Date()
    @Published var extensionsRemaining: Int
    @Published var overridesRemaining: Int
    @Published var lockoutMessage: String
    @Published var overrideReasonDraft: String = ""
    @Published var overrideCooldownEndsAt: Date?
    @Published var isOverrideComposerVisible = false
    @Published var shutdownStatusLine: String?
    @Published private(set) var overrideEvents: [OverrideEvent]

    private let settingsStore: CurfewSettingsStore
    private let policyEngine: SchedulePolicyEngine
    private let enforcementEngine: CurfewEnforcementEngine
    private let notificationManager: WarningNotificationManager
    private let overlayCoordinator: OverlayCoordinator
    private let lockoutKeyInterceptor: LockoutKeyInterceptor
    private let shutdownController: ShutdownControlling
    private let appRouter: AppRouting
    private let gettingStartedPresenter: GettingStartedPresenting
    private var extensionTracker: ExtensionBudgetTracker
    private var overrideTracker: ExtensionBudgetTracker
    private var timer: Timer?
    private var extensionMinutesGrantedToday = 0
    private var snoozeMinutesGrantedToday = 0
    private var currentDayToken = ""
    private var overrideUntil: Date?
    private var shutdownWorkflow = ShutdownWorkflow()
    private var started = false

    override init() {
        let settingsStore = CurfewSettingsStore()
        let policyEngine = SchedulePolicyEngine()
        let enforcementEngine = CurfewEnforcementEngine()
        let notificationManager = WarningNotificationManager()
        let overlayCoordinator = OverlayCoordinator()
        let lockoutKeyInterceptor = LockoutKeyInterceptor()
        let shutdownController = SystemShutdownController()
        let loadedSettings = settingsStore.load()
        self.settingsStore = settingsStore
        self.policyEngine = policyEngine
        self.enforcementEngine = enforcementEngine
        self.notificationManager = notificationManager
        self.overlayCoordinator = overlayCoordinator
        self.lockoutKeyInterceptor = lockoutKeyInterceptor
        self.shutdownController = shutdownController
        self.appRouter = SystemAppRouter()
        self.gettingStartedPresenter = GettingStartedWindowPresenter()
        self.featureFlags = .default
        self.settings = loadedSettings
        self.shouldOpenSettingsOnLaunch = settingsStore.consumeShouldShowInitialSetup()
        self.overrideEvents = settingsStore.loadOverrideEvents()

        self.extensionTracker = ExtensionBudgetTracker(
            weeklyLimit: loadedSettings.extensionWeeklyLimit,
            extensionMinutes: loadedSettings.extensionDurationMinutes,
            resetWeekday: loadedSettings.resetWeekday
        )
        self.overrideTracker = ExtensionBudgetTracker(
            weeklyLimit: loadedSettings.overrideWeeklyLimit,
            extensionMinutes: loadedSettings.overrideDurationMinutes,
            resetWeekday: loadedSettings.resetWeekday
        )

        let now = Date()
        let initialState = Self.initialEvaluation(
            settings: loadedSettings,
            now: now,
            enforcementEngine: enforcementEngine
        )

        self.state = initialState
        self.extensionsRemaining = extensionTracker.remaining
        self.overridesRemaining = overrideTracker.remaining
        self.lockoutMessage = EncouragementMessageCatalog.next(after: nil)
        self.shutdownStatusLine = nil
        self.currentDayToken = Self.dayToken(for: now)
        super.init()

        configureNotificationCallback()
    }

    init(
        settingsStore: CurfewSettingsStore,
        appRouter: AppRouting,
        gettingStartedPresenter: GettingStartedPresenting,
        featureFlags: FeatureFlags = FeatureFlags(
            widgetKitEnabled: false,
            cloudSyncEnabled: false,
            mcpServerEnabled: false,
            privilegedHelperEnabled: false
        )
    ) {
        let policyEngine = SchedulePolicyEngine()
        let enforcementEngine = CurfewEnforcementEngine()
        let notificationManager = WarningNotificationManager()
        let overlayCoordinator = OverlayCoordinator()
        let lockoutKeyInterceptor = LockoutKeyInterceptor()
        let shutdownController = SystemShutdownController()
        let loadedSettings = settingsStore.load()
        self.settingsStore = settingsStore
        self.policyEngine = policyEngine
        self.enforcementEngine = enforcementEngine
        self.notificationManager = notificationManager
        self.overlayCoordinator = overlayCoordinator
        self.lockoutKeyInterceptor = lockoutKeyInterceptor
        self.shutdownController = shutdownController
        self.appRouter = appRouter
        self.gettingStartedPresenter = gettingStartedPresenter
        self.featureFlags = featureFlags
        self.settings = loadedSettings
        self.shouldOpenSettingsOnLaunch = settingsStore.consumeShouldShowInitialSetup()
        self.overrideEvents = settingsStore.loadOverrideEvents()

        self.extensionTracker = ExtensionBudgetTracker(
            weeklyLimit: loadedSettings.extensionWeeklyLimit,
            extensionMinutes: loadedSettings.extensionDurationMinutes,
            resetWeekday: loadedSettings.resetWeekday
        )
        self.overrideTracker = ExtensionBudgetTracker(
            weeklyLimit: loadedSettings.overrideWeeklyLimit,
            extensionMinutes: loadedSettings.overrideDurationMinutes,
            resetWeekday: loadedSettings.resetWeekday
        )

        let now = Date()
        let initialState = Self.initialEvaluation(
            settings: loadedSettings,
            now: now,
            enforcementEngine: enforcementEngine
        )

        self.state = initialState
        self.extensionsRemaining = extensionTracker.remaining
        self.overridesRemaining = overrideTracker.remaining
        self.lockoutMessage = EncouragementMessageCatalog.next(after: nil)
        self.shutdownStatusLine = nil
        self.currentDayToken = Self.dayToken(for: now)
        super.init()

        configureNotificationCallback()
    }

    convenience init(
        appRouter: AppRouting,
        gettingStartedPresenter: GettingStartedPresenting
    ) {
        self.init(
            settingsStore: CurfewSettingsStore(),
            appRouter: appRouter,
            gettingStartedPresenter: gettingStartedPresenter
        )
    }

    private func configureNotificationCallback() {
        notificationManager.onSnoozeRequested = { [weak self] in
            self?.requestNotificationSnooze()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard settings.hasCompletedInitialSetup else {
            return
        }
        guard !started else {
            return
        }
        started = true
        notificationManager.requestPermissionIfNeeded()
        tick()
        timer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(handleTimerFire(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    var isEnforcementRunning: Bool {
        started
    }

    func completeInitialSetup() {
        guard !settings.hasCompletedInitialSetup else {
            return
        }
        settings.hasCompletedInitialSetup = true
        start()
    }

    func openSettings() {
        appRouter.activate()
        appRouter.showSettings()
    }

    func showGettingStarted() {
        appRouter.activate()
        gettingStartedPresenter.present(model: self)
    }

    func dismissGettingStarted() {
        gettingStartedPresenter.dismiss()
    }

    func completeOnboardingFlow() {
        completeInitialSetup()
        dismissGettingStarted()
    }

    @objc
    private func handleTimerFire(_ timer: Timer) {
        tick()
    }

    var menuBarSymbolName: String {
        symbolName(for: state.phase)
    }

    var statusLine: String {
        statusLine(for: state.phase)
    }

    var timeRemainingText: String {
        timeRemainingText(for: state.minutesRemaining)
    }

    var snapshot: EnforcementSnapshot {
        EnforcementSnapshot(
            phase: state.phase,
            symbolName: symbolName(for: state.phase),
            statusLine: statusLine(for: state.phase),
            timeRemainingText: timeRemainingText(for: state.minutesRemaining),
            scheduleWindowText: scheduleWindowText,
            scheduleSummarySentence: scheduleSummarySentence,
            pendingScheduleDescription: pendingScheduleDescription,
            canRequestExtension: state.canRequestExtension,
            extensionRequestTitle: "Hold \(Int(Self.extensionConfirmationHoldSeconds))s for +\(settings.extensionDurationMinutes)m extension",
            extensionsRemaining: extensionsRemaining
        )
    }

    var editableSchedule: WeeklySchedule {
        settings.pendingScheduleChange?.proposedSchedule ?? settings.schedule
    }

    var pendingScheduleDescription: String? {
        guard let pending = settings.pendingScheduleChange else {
            return nil
        }
        let timestamp = pending.effectiveAt.formatted(date: .abbreviated, time: .shortened)
        switch pending.classification {
        case .weaker:
            return "A less strict schedule is queued for \(timestamp)."
        case .stricter:
            return "A stricter schedule is queued for \(timestamp)."
        case .noChange:
            return nil
        }
    }

    var scheduleSummarySentence: String {
        editableSchedule.summarySentence(forNextDayFrom: currentTime)
    }

    private var scheduleWindowText: String {
        guard let lockDate = state.lockDate, let unlockDate = state.unlockDate else {
            return "No enforcement window is active today."
        }
        return "\(lockDate.formatted(date: .omitted, time: .shortened)) -> \(unlockDate.formatted(date: .omitted, time: .shortened))"
    }

    var overrideCooldownRemaining: Int {
        guard let overrideCooldownEndsAt else {
            return 0
        }
        return max(0, Int(overrideCooldownEndsAt.timeIntervalSince(currentTime)))
    }

    var canConfirmOverride: Bool {
        OverrideRequestPolicy.canConfirm(
            reason: overrideReasonDraft,
            now: currentTime,
            cooldownEndsAt: overrideCooldownEndsAt,
            overridesRemaining: overridesRemaining
        )
    }

    func applyPreset(_ preset: SchedulePreset) {
        switch preset {
        case .nineToFive:
            queueScheduleUpdate(.standardNineToFive)
        case .startupHours:
            queueScheduleUpdate(.startupHours)
        case .halfDay:
            queueScheduleUpdate(.halfDay)
        }
    }

    func updateRule(for day: Weekday, update: (inout DayRule) -> Void) {
        var nextSchedule = editableSchedule
        var rule = nextSchedule.rule(for: day)
        update(&rule)
        nextSchedule.rules[day] = rule
        queueScheduleUpdate(nextSchedule)
    }

    func tapExtensionRequest() {}

    func confirmExtensionRequest() {
        guard state.canRequestExtension else {
            return
        }
        guard extensionTracker.requestExtension(at: currentTime) else {
            extensionsRemaining = extensionTracker.remaining
            return
        }

        extensionsRemaining = extensionTracker.remaining
        extensionMinutesGrantedToday += settings.extensionDurationMinutes
        tick()
    }

    func requestNotificationSnooze() {
        guard state.warningStage.supportsSnooze else {
            return
        }
        snoozeMinutesGrantedToday += 1
        tick()
    }

    func beginOverrideRequest() {
        guard state.phase == .locked else {
            return
        }
        guard overridesRemaining > 0 else {
            isOverrideComposerVisible = false
            return
        }
        if overrideCooldownEndsAt == nil {
            overrideCooldownEndsAt = OverrideRequestPolicy.cooldownEnd(startedAt: currentTime)
        }
        if overrideCooldownRemaining == 0 {
            isOverrideComposerVisible = true
        }
    }

    func confirmOverride() {
        guard canConfirmOverride else {
            return
        }
        guard overrideTracker.requestExtension(at: currentTime) else {
            overridesRemaining = overrideTracker.remaining
            return
        }

        let reason = trimmedOverrideReason
        overrideUntil = currentTime.addingTimeInterval(TimeInterval(settings.overrideDurationMinutes * 60))
        overridesRemaining = overrideTracker.remaining
        overrideReasonDraft = ""
        overrideCooldownEndsAt = nil
        isOverrideComposerVisible = false
        lockoutMessage = "Welcome back. Hope you got what you needed."
        let event = OverrideEvent(
            timestamp: currentTime,
            deviceName: currentDeviceName(),
            reason: reason,
            grantedDurationMinutes: settings.overrideDurationMinutes
        )
        settingsStore.appendOverrideEvent(event)
        overrideEvents.append(event)
        tick()
    }

    private var trimmedOverrideReason: String {
        overrideReasonDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func queueScheduleUpdate(_ proposedSchedule: WeeklySchedule) {
        let classification = policyEngine.classifyChange(from: settings.schedule, to: proposedSchedule)
        if classification == .noChange {
            settings.pendingScheduleChange = nil
            persistSettings()
            tick()
            return
        }

        let effectiveDate = policyEngine.earliestEffectiveDate(
            for: classification,
            requestedAt: currentTime
        )
        settings.pendingScheduleChange = PendingScheduleChange(
            proposedSchedule: proposedSchedule,
            requestedAt: currentTime,
            effectiveAt: effectiveDate,
            classification: classification
        )
        persistSettings()
        tick()
    }

    private func tick() {
        let previousPhase = state.phase
        currentTime = Date()

        if Self.dayToken(for: currentTime) != currentDayToken {
            currentDayToken = Self.dayToken(for: currentTime)
            extensionMinutesGrantedToday = 0
            snoozeMinutesGrantedToday = 0
        }

        applyPendingScheduleIfNeeded(now: currentTime)

        extensionTracker.resetIfNeeded(at: currentTime)
        overrideTracker.resetIfNeeded(at: currentTime)
        extensionsRemaining = extensionTracker.remaining
        overridesRemaining = overrideTracker.remaining

        state = enforcementEngine.evaluate(
            at: currentTime,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: extensionMinutesGrantedToday + snoozeMinutesGrantedToday,
            overrideUntil: overrideUntil,
            warningIntervals: settings.warningIntervals
        )

        if previousPhase != .locked, state.phase == .locked {
            lockoutMessage = EncouragementMessageCatalog.next(after: lockoutMessage)
        }

        reconcileOverrideComposerState(previousPhase: previousPhase)
        notificationManager.update(stage: state.warningStage, now: currentTime)
        updateLockoutInterception(for: state.phase)
        updateShutdownWorkflow()
        overlayCoordinator.updateOverlays(for: state, model: self, lockoutMessage: lockoutMessage)
    }

    func reconcileOverrideComposerState(previousPhase: EnforcementPhase) {
        if previousPhase == .locked, state.phase != .locked {
            overrideCooldownEndsAt = nil
            isOverrideComposerVisible = false
            overrideReasonDraft = ""
            return
        }

        guard state.phase == .locked else {
            return
        }

        guard overridesRemaining > 0 else {
            isOverrideComposerVisible = false
            return
        }

        guard overrideCooldownEndsAt != nil else {
            isOverrideComposerVisible = false
            return
        }

        if overrideCooldownRemaining == 0 {
            isOverrideComposerVisible = true
        } else {
            isOverrideComposerVisible = false
        }
    }

    private func applyPendingScheduleIfNeeded(now: Date) {
        guard let pending = settings.pendingScheduleChange else {
            return
        }
        guard now >= pending.effectiveAt else {
            return
        }
        settings.schedule = pending.proposedSchedule
        settings.pendingScheduleChange = nil
        persistSettings()
    }

    private func persistSettings() {
        settingsStore.save(settings)
    }

    private func handleSettingsMutation(from oldValue: CurfewSettings) {
        if settings.resetWeekday != oldValue.resetWeekday ||
            settings.extensionWeeklyLimit != oldValue.extensionWeeklyLimit ||
            settings.extensionDurationMinutes != oldValue.extensionDurationMinutes {
            let usedExtensions = max(0, oldValue.extensionWeeklyLimit - extensionsRemaining)
            extensionTracker = ExtensionBudgetTracker(
                weeklyLimit: settings.extensionWeeklyLimit,
                extensionMinutes: settings.extensionDurationMinutes,
                resetWeekday: settings.resetWeekday
            )
            if usedExtensions > 0 {
                for _ in 0..<usedExtensions where extensionTracker.remaining > 0 {
                    _ = extensionTracker.requestExtension(at: currentTime)
                }
            }
            extensionsRemaining = extensionTracker.remaining
        }

        if settings.resetWeekday != oldValue.resetWeekday ||
            settings.overrideWeeklyLimit != oldValue.overrideWeeklyLimit ||
            settings.overrideDurationMinutes != oldValue.overrideDurationMinutes {
            let usedOverrides = max(0, oldValue.overrideWeeklyLimit - overridesRemaining)
            overrideTracker = ExtensionBudgetTracker(
                weeklyLimit: settings.overrideWeeklyLimit,
                extensionMinutes: settings.overrideDurationMinutes,
                resetWeekday: settings.resetWeekday
            )
            if usedOverrides > 0 {
                for _ in 0..<usedOverrides where overrideTracker.remaining > 0 {
                    _ = overrideTracker.requestExtension(at: currentTime)
                }
            }
            overridesRemaining = overrideTracker.remaining
        }

        persistSettings()
    }

    private func updateLockoutInterception(for phase: EnforcementPhase) {
        if phase == .locked {
            lockoutKeyInterceptor.start()
        } else {
            lockoutKeyInterceptor.stop()
        }
    }

    private func updateShutdownWorkflow() {
        shutdownWorkflow.update(
            now: currentTime,
            isLocked: state.phase == .locked,
            isEnabled: settings.autoShutdownEnabled,
            delayMinutes: settings.autoShutdownDelayMinutes,
            controller: shutdownController
        )
        shutdownStatusLine = shutdownWorkflow.statusLine(now: currentTime)
    }

    private func symbolName(for phase: EnforcementPhase) -> String {
        switch phase {
        case .working:
            return "clock.badge.checkmark"
        case .warning:
            return "exclamationmark.triangle"
        case .locked:
            return "lock.fill"
        case .dayOff:
            return "moon.zzz"
        }
    }

    private func statusLine(for phase: EnforcementPhase) -> String {
        switch phase {
        case .working:
            return "Working window active"
        case .warning:
            return "Wrap up time"
        case .locked:
            return "Curfew lockout active"
        case .dayOff:
            return "Day off"
        }
    }

    private func timeRemainingText(for minutesRemaining: Int) -> String {
        if minutesRemaining == .max {
            return "—"
        }
        let minutes = max(0, minutesRemaining)
        let hoursComponent = minutes / 60
        let minuteComponent = minutes % 60
        return String(format: "%d:%02d", hoursComponent, minuteComponent)
    }

    private static func dayToken(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private static func initialEvaluation(
        settings: CurfewSettings,
        now: Date,
        enforcementEngine: CurfewEnforcementEngine
    ) -> CurfewEvaluation {
        guard settings.hasCompletedInitialSetup else {
            return CurfewEvaluation(
                phase: .dayOff,
                warningStage: .none,
                minutesRemaining: .max,
                canRequestExtension: false,
                lockDate: nil,
                unlockDate: nil
            )
        }

        return enforcementEngine.evaluate(
            at: now,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: settings.warningIntervals
        )
    }

    private func currentDeviceName() -> String {
        if let localized = Host.current().localizedName, !localized.isEmpty {
            return localized
        }
        if !ProcessInfo.processInfo.hostName.isEmpty {
            return ProcessInfo.processInfo.hostName
        }
        return "Unknown Device"
    }
}
