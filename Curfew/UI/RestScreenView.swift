import CoreGraphics
import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// One continuous scene per display: the sky, the lock or the morning, and
/// the arrival that plays the first time the window is seen. Content changes
/// without replacing the window, sky or editing session.
struct RestScreenView: View {
    let model: CurfewAppModel
    @Bindable var display: RestDisplayPresentation
    let scene: LockScene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var backgroundImage: CGImage?
    @State private var hostID = UUID()
    @Namespace private var clockTransition
    @State private var coverOpacity: Double
    @State private var previousContent: RestContentState

    init(model: CurfewAppModel, display: RestDisplayPresentation, scene: LockScene) {
        self.model = model
        self.display = display
        self.scene = scene
        _coverOpacity = State(initialValue: display.isVisible ? 0 : 1)
        _previousContent = State(initialValue: model.restPresentation.layout)
    }

    private var choreography: RestAppearance.Transition {
        RestAppearance.standard.transition(
            from: previousContent, to: content, reduceMotion: reduceMotion
        )
    }

    private var motion: RestAppearance.Motion {
        RestAppearance.standard.motion(reduceMotion: reduceMotion)
    }

    private var content: RestContentState {
        model.restPresentation.layout
    }

    private var showsMorning: Bool {
        content == .morning && !model.isEnforcingLockout
    }

    private var clockDesign: Font.Design {
        switch model.restAppearance.clockStyle {
        case .rounded: .rounded
        case .standard: .default
        case .serif: .serif
        }
    }

    var sceneSnapshot: RestSceneSnapshot {
        let interval = model.reflectionState.scheduledInterval
        let candidate = interval?.end
        let unlock = candidate == .distantFuture ? nil : candidate
        return RestSceneSnapshot(
            version: 1,
            expiresAt: unlock?.addingTimeInterval(3600) ?? model.currentTime
                .addingTimeInterval(300),
            appearance: model.restAppearance,
            lockDate: interval.map { scene.anchoredCurfew($0.start) },
            unlockDate: unlock
        )
    }

    /// The lock's sky at `date`: the night the lock shows, reached from the
    /// sky the person was looking at over the arrival's first seconds.
    func lockFrame(fallback: HorizonFrame, at date: Date) -> HorizonFrame {
        guard !showsMorning else { return fallback }
        var moment = model.horizonMoment()
        moment.now = date
        moment.curfew = scene.anchoredCurfew(moment.curfew)
        guard date >= moment.curfew, date < moment.nextUnlock else { return fallback }
        let night = LockSceneSky.frame(for: moment)
        let start = scene.startingFrame ?? night
        return LockSceneSky.blend(start, night, amount: scene.timeline.sky(at: date))
    }

    private var morningClock: some View {
        Text(model.currentTime, style: .time)
            .font(.system(size: 64, weight: .semibold, design: clockDesign))
            .monospacedDigit()
            .foregroundStyle(SundownPalette.warmWhite)
            .matchedGeometryEffect(id: "rest-clock", in: clockTransition)
            .accessibilityIdentifier("rest-clock")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TimelineView(.animation(
                    minimumInterval: scene.timeline.stage(at: Date()) == .arriving
                        ? 1.0 / 30 :
                        (reduceMotion || model.restAppearance.staticBackground ? 1 : 1.0 / 24),
                    paused: !display.isVisible
                )) { context in
                    let date = model.isDemoSession ? model.currentTime : context.date
                    RestAmbientScene(
                        snapshot: sceneSnapshot,
                        date: date,
                        image: backgroundImage,
                        reduceMotion: reduceMotion,
                        reduceTransparency: reduceTransparency,
                        showsClock: model.restHandoffIsAmbient,
                        clockSize: max(20, min(geometry.size.width, geometry.size.height) * 0.10),
                        clockNamespace: clockTransition
                    ) { frame, drifts in
                        HorizonSkyView(
                            frame: lockFrame(fallback: frame, at: date),
                            isDayRunning: drifts
                        )
                    }
                    .overlay {
                        if !showsMorning {
                            LockoutScreenView(scene: scene, date: date)
                                .environment(model)
                                .opacity(model.restHandoffIsAmbient ? 0 : 1)
                                .accessibilityHidden(model.restHandoffIsAmbient)
                                .allowsHitTesting(interactive)
                        }
                    }
                }
                .ignoresSafeArea()
                if showsMorning {
                    morning(in: geometry.size)
                }
                Color.black.opacity(display.isVisible ? coverOpacity : 1)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(.easeInOut(duration: motion.layoutDuration), value: model.restHandoffIsAmbient)
        .onAppear { model.restRuntime.handoff.visibleHosts.insert(hostID) }
        .onDisappear { model.restRuntime.handoff.visibleHosts.remove(hostID) }
        .task(id: model.restAppearance.ownedImageFilename) {
            let directory = model.restBackgroundDirectory
            let filename = model.restAppearance.ownedImageFilename
            let image = await Task.detached(priority: .userInitiated) {
                RestBackgroundImageStore(directory: directory).image(named: filename)
            }.value
            guard !Task.isCancelled else { return }
            backgroundImage = image
        }
        .onChange(of: content) { _, newContent in previousContent = newContent }
        .onChange(of: display.isVisible) { _, visible in
            if !visible {
                coverOpacity = 1
            }
        }
        .task(id: display.isVisible ? display.revealGeneration : -1) {
            await reveal()
        }
    }

    private var interactive: Bool {
        display.isVisible && coverOpacity == 0 && !model.restHandoffIsAmbient
    }

    /// The morning keeps its own layout; the Sunrise gate owns its content.
    private func morning(in size: CGSize) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                if !model.restHandoffIsAmbient {
                    morningClock
                }
                DaybreakReflectionView()
                    .transition(.opacity.combined(with: .offset(y: motion.translation)))
                    .animation(
                        .easeOut(duration: motion.contentDuration)
                            .delay(choreography.contentDelay), value: content
                    )
                Spacer(minLength: 0)
            }
            .padding(CurfewSpacing.xLarge)
            .frame(maxWidth: .infinity, minHeight: size.height)
        }
        .scrollIndicators(.hidden)
        .environment(model)
        .opacity(model.restHandoffIsAmbient ? 0 : 1)
        .accessibilityHidden(model.restHandoffIsAmbient)
        .allowsHitTesting(interactive)
    }

    /// The first sighting starts the shared arrival with no cover: the window
    /// already shows the sky the person was looking at. Later sightings, after
    /// sleep or a screen saver, fade in from black so a stale frame never shows.
    private func reveal() async {
        guard display.revealGeneration > 0, display.isVisible else { return }
        let now = Date()
        if scene.timeline.stage(at: now) == .waitingToBeSeen
            || scene.timeline.stage(at: now) == .arriving {
            scene.seen(at: now, reduceMotion: reduceMotion)
            coverOpacity = 0
            return
        }
        coverOpacity = 1
        do {
            try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 200))
            try Task.checkCancellation()
            withAnimation(.easeOut(duration: motion.revealDuration)) {
                coverOpacity = 0
            }
        } catch { /* A later lifecycle event owns the next reveal. */ }
    }
}

/// The lock's screen saver control. It appears only when it does something:
/// "Start the screen saver" when Curfew may hand off, or, outside the lock,
/// a way to set up Curfew's saver when that is what is missing. A saver that
/// is already running needs neither.
struct RestSaverControl: View {
    @Environment(CurfewAppModel.self) private var model

    var body: some View {
        if model.canRestNow {
            QuietLockButton(title: "Start the screen saver", symbol: .lastNight) {
                model.restNow()
            }
            .accessibilityIdentifier("rest-now")
        } else if !model.isEnforcingLockout, let missing = model.restSaverMissing {
            QuietLockButton(title: Self.setupTitle(for: missing), symbol: .lastNight) {
                model.openRestScreenSetup()
            }
            .accessibilityIdentifier("rest-saver-setup")
        }
    }

    static func setupTitle(for missing: RestSaverChoice.Missing) -> String {
        switch missing {
        case .curfewSaverNotSelected: "Set up Curfew's screen saver"
        case .curfewSaverNotProven: "Finish setting up Curfew's screen saver"
        }
    }
}
