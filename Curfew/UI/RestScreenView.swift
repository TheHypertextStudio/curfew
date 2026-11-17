import CoreGraphics
import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// A still rest screen for the theme editor: the lock (or the screen saver's
/// clock) at a fixed moment of a fixed night, drawn by the real views from
/// the person's current theme. Nothing on it can be pressed, takes focus,
/// announces itself or joins the screen saver handoff.
struct RestScreenPreview: Equatable {
    enum Subject: Equatable {
        /// The lock: clock, headline, unlock line and the override entry.
        case lock
        /// The idle scene the screen saver shows: the sky and the clock.
        case screenSaver
    }

    var subject: Subject
    var now: Date
    var curfew: Date
    var unlock: Date

    /// 9:41 PM tonight, after a 6:00 PM curfew, unlocking at 7:00 AM.
    static func tonight(
        _ subject: Subject, near reference: Date, calendar: Calendar = .current
    ) -> RestScreenPreview {
        let day = calendar.startOfDay(for: reference)
        func at(_ hour: Int, _ minute: Int, days: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: days, to: day) ?? day
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
                ?? base
        }
        return RestScreenPreview(
            subject: subject, now: at(21, 41), curfew: at(18, 0), unlock: at(7, 0, days: 1)
        )
    }

    /// The lock's night sky at this moment, with tonight's moon.
    var frame: HorizonFrame {
        LockSceneSky.frame(for: HorizonMoment(
            now: now, dayStart: unlock.addingTimeInterval(-24 * 3600), curfew: curfew,
            nextUnlock: unlock
        ))
    }
}

/// One continuous scene per display: the sky, the lock or the morning, and
/// the arrival that plays the first time the window is seen. Content changes
/// without replacing the window, sky or editing session.
struct RestScreenView: View {
    let model: CurfewAppModel
    @Bindable var display: RestDisplayPresentation
    let scene: LockScene
    /// Set by the theme editor: draw a still preview instead of the live lock.
    var preview: RestScreenPreview?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var backgroundImage: CGImage?
    @State private var hostID = UUID()
    @Namespace private var clockTransition
    @State private var coverOpacity: Double
    @State private var previousContent: RestContentState

    init(
        model: CurfewAppModel, display: RestDisplayPresentation, scene: LockScene,
        preview: RestScreenPreview? = nil
    ) {
        self.model = model
        self.display = display
        self.scene = scene
        self.preview = preview
        _coverOpacity = State(initialValue: display.isVisible || preview != nil ? 0 : 1)
        _previousContent = State(
            initialValue: preview == nil ? model.restPresentation.layout : .quiet
        )
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
        preview == nil ? model.restPresentation.layout : .quiet
    }

    private var showsMorning: Bool {
        preview == nil && content == .morning && !model.isEnforcingLockout
    }

    /// Whether the scene shows the screen saver's clock instead of the lock.
    private var isAmbient: Bool {
        preview.map { $0.subject == .screenSaver } ?? model.restHandoffIsAmbient
    }

    private var clockDesign: Font.Design {
        model.restAppearance.clockStyle.fontDesign
    }

    var sceneSnapshot: RestSceneSnapshot {
        if let preview {
            return RestSceneSnapshot(
                version: 1, expiresAt: .distantFuture, appearance: model.restAppearance,
                lockDate: preview.curfew, unlockDate: preview.unlock
            )
        }
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
        if let preview {
            return preview.frame
        }
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
                    paused: !display.isVisible || preview != nil
                )) { context in
                    let date = preview?.now
                        ?? (model.isDemoSession ? model.currentTime : context.date)
                    RestAmbientScene(
                        snapshot: sceneSnapshot,
                        date: date,
                        image: backgroundImage,
                        reduceMotion: reduceMotion,
                        reduceTransparency: reduceTransparency,
                        showsClock: isAmbient,
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
                            LockoutScreenView(
                                scene: preview == nil ? scene : nil,
                                date: preview == nil ? scene.timeline.wordsDate(at: date) : date,
                                preview: preview
                            )
                            .environment(model)
                            .opacity(isAmbient ? 0 : 1)
                            .accessibilityHidden(isAmbient)
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
        .animation(.easeInOut(duration: motion.layoutDuration), value: isAmbient)
        .onAppear {
            if preview == nil {
                model.restRuntime.handoff.visibleHosts.insert(hostID)
            }
        }
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
        preview == nil && display.isVisible && coverOpacity == 0 && !model.restHandoffIsAmbient
    }

    /// The morning keeps its own layout; the Sunrise gate owns its content.
    private func morning(in size: CGSize) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                if !model.restHandoffIsAmbient {
                    morningClock
                }
                SunriseGateView()
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
        guard preview == nil, display.revealGeneration > 0, display.isVisible else { return }
        // The arrival runs on the clock the scene is drawn with: the demo
        // fixture's own clock, so its lock arrives the same at any hour.
        let now = model.isDemoSession ? model.currentTime : Date()
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
