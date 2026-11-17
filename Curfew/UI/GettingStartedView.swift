import AppKit
import CurfewKit
import SwiftUI

/// First-run setup, hosted by the `getting-started` window.
///
/// One sky and one thing per screen:
/// 1. A welcome. The sky plays one day behind three captions, then rests.
/// 2. When should your day end? (an explicit schedule choice; the unlock time
///    and the days sit behind "Change")
/// 3. Let Curfew hold the lock. (Accessibility, required) Setup commits the
///    moment access is granted.
/// 4. Notifications and the Curfew helper, both optional.
/// 5. You're set. States tonight's curfew and previews the lock.
/// Then sync and the lifetime licence, which can be skipped as easily.
///
/// Progress is saved on every step change so setup reopens where the person
/// left it until it is completed.
struct GettingStartedView: View {
    @Environment(CurfewAppModel.self) var model
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State var flow: FirstRunFlow
    @State var hasLoaded: Bool
    @State var draft: SetupScheduleDraft?
    @State var editingMorning: Bool
    @State var notificationStatus: SetupPermissionStatus
    @State var optionalAsks: [SetupOptionalAsk] = [.notifications, .helper]
    @State var dragHelper: AccessibilityDragHelper?
    @State var waitingForAccess = false
    @State var movingOn = false
    @State var preview: LockPreviewController?
    @State var confirmingImmediateLock = false
    @State var signedIn = false
    @State var story: SetupSkyStory
    @State var entranceDelay = 0.0
    @State var introPhase = SetupIntroPhase.rest
    @State var introStart: Date?
    @State var introTask: Task<Void, Never>?

    /// `nil` uses the system; fixed values serve snapshots.
    let notifications: (any NotificationPermissionProviding)?
    /// `nil` uses the app's account enrollment, the same one Settings uses.
    let makeAccount: (@MainActor () -> AccountEnrollmentController)?
    let now: () -> Date
    /// A fixed flow is a still picture: no welcome day, no sweeps.
    let isLive: Bool

    /// - Parameters:
    ///   - flow: A fixed cursor for snapshots; `nil` loads saved progress.
    ///   - editingMorning: Shows the unlock and days screen of the question.
    ///   - notifications: Reads and requests notification permission.
    ///   - notificationStatus: The status shown before the first read.
    init(
        flow: FirstRunFlow? = nil,
        editingMorning: Bool = false,
        notifications: (any NotificationPermissionProviding)? = nil,
        notificationStatus: SetupPermissionStatus = .notAsked,
        makeAccount: (@MainActor () -> AccountEnrollmentController)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let start = flow ?? FirstRunFlow()
        self.makeAccount = makeAccount
        self.isLive = flow == nil
        _flow = State(initialValue: start)
        _hasLoaded = State(initialValue: flow != nil)
        _editingMorning = State(initialValue: editingMorning)
        _notificationStatus = State(initialValue: notificationStatus)
        // A live setup opens on the welcome's title card, before dawn, so the
        // first frame is already the start of its day.
        _story = State(initialValue: flow == nil
            ? SetupSkyStory(at: SetupSky.Intro.minute(at: 0))
            : SetupSkyStory(
                restingOn: Self.scene(for: start.currentStep, editingMorning: editingMorning)
            ))
        _introPhase = State(initialValue: flow == nil ? .title : .rest)
        self.notifications = notifications
        self.now = now
    }

    var body: some View {
        GeometryReader { proxy in
            let band = SetupSky.textBand
            ZStack {
                SetupSkyBackdrop(story: story, introStart: introStart)
                GettingStartedScaffold(
                    scene: scene,
                    headline: headline,
                    wordmark: wordmark,
                    secondary: secondaryAction,
                    primary: primaryAction,
                    delay: entranceDelay,
                    animates: animates
                ) {
                    content
                }
                .frame(
                    width: proxy.size.width * band.width,
                    height: proxy.size.height * band.height
                )
                .position(x: proxy.size.width * band.midX, y: proxy.size.height * band.midY)
            }
            .environment(\.setupMetrics, SetupMetrics.window(proxy.size))
        }
        // The sky and the text band are both measured from the whole window,
        // title bar included, so the band the contrast tests sample is exact.
        .ignoresSafeArea()
        .frame(
            minWidth: GettingStartedLayout.contentMinimum.width,
            idealWidth: GettingStartedLayout.windowSize.width,
            minHeight: GettingStartedLayout.contentMinimum.height,
            idealHeight: GettingStartedLayout.windowSize.height
        )
        .foregroundStyle(GettingStartedPalette.ink)
        .tint(GettingStartedPalette.ink)
        .onAppear(perform: load)
        .task {
            #if DEBUG
                await runCaptureWalkthrough()
            #endif
        }
        .onDisappear {
            introTask?.cancel()
            dragHelper?.stop()
            preview?.dismiss()
        }
        .onChange(of: flow.currentStep) { _, step in stepChanged(to: step) }
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
                change { flow.retreat() }
            }
        } message: {
            Text(GettingStartedCopy.immediateLockMessage)
        }
    }
}

// MARK: Scenes and the sky

extension GettingStartedView {
    static func scene(for step: FirstRunStep, editingMorning: Bool) -> SetupScene {
        switch step {
        case .welcome: .welcome
        case .schedule: editingMorning ? .morning : .schedule
        case .permissions: .permissions
        case .optional: .optional
        case .ready: .ready
        case .extras: .extras
        }
    }

    var scene: SetupScene {
        Self.scene(for: flow.currentStep, editingMorning: editingMorning)
    }

    var animates: Bool {
        isLive && !reduceMotion
    }

    func load() {
        if !hasLoaded {
            hasLoaded = true
            flow = model.loadSetupFlow()
            if flow.currentStep != .welcome {
                story = SetupSkyStory(restingOn: scene)
                introPhase = .rest
            }
        }
        if draft == nil {
            draft = model.setupScheduleDraft
        }
        if !model.isDemoSession {
            model.refreshAccessibilityTrust()
            model.privilegedHelperManager.refreshStatus()
        }
        flow.updateAccessibilityGranted(model.isAccessibilityTrusted)
        refreshPermissions()
        stepChanged(to: flow.currentStep, announce: false)
        if flow.currentStep == .welcome, isLive {
            playIntro()
        }
    }

    /// Every move between screens goes through here, so the sky sets off for
    /// the next screen's hour in the same update that swaps the screen, and
    /// the screen knows how long to wait for it.
    func change(_ update: () -> Void) {
        let before = scene
        withAnimation(animates ? .easeInOut(duration: 0.3) : .easeOut(duration: 0.2)) {
            update()
            let after = scene
            guard before != after else { return }
            stopIntro()
            let distance = story.move(to: after, at: Date(), animated: animates)
            entranceDelay = animates ? SetupSky.entranceDelay(distance: distance) : 0
        }
    }

    /// Plays the welcome's day: the title card, three captions, then rest.
    func playIntro() {
        introTask?.cancel()
        guard animates else {
            introStart = nil
            introPhase = .rest
            story = SetupSkyStory(restingOn: .welcome)
            return
        }
        let start = Date()
        entranceDelay = 0
        withAnimation(.easeOut(duration: 0.4)) {
            introStart = start
            introPhase = .title
        }
        var cues: [(Double, SetupIntroPhase)] = [(SetupSky.Intro.titleSettles, .settled)]
        cues += SetupSky.Intro.captionTimes.enumerated().map { ($1, .caption($0)) }
        cues.append((SetupSky.Intro.duration, .rest))
        introTask = Task { @MainActor in
            for (time, phase) in cues {
                let wait = start.addingTimeInterval(time).timeIntervalSinceNow
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) {
                    introPhase = phase
                }
            }
            story = SetupSkyStory(restingOn: .welcome)
            introStart = nil
        }
    }

    /// Leaves the welcome's day wherever it has got to, so the sky carries on
    /// from there.
    func stopIntro() {
        introTask?.cancel()
        introTask = nil
        if let introStart {
            story = SetupSkyStory(
                at: SetupSky.Intro.minute(at: Date().timeIntervalSince(introStart))
            )
        }
        introStart = nil
        introPhase = .rest
    }
}
