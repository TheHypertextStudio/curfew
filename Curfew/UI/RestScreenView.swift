import CoreGraphics
import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// One continuous atmosphere and clock, independent of restriction authority.
/// Content can change without replacing the window, sky, or editing session.
struct RestScreenView: View {
    let model: CurfewAppModel
    @Bindable var display: RestDisplayPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var backgroundImage: CGImage?
    @State private var coverOpacity: Double
    @State private var previousContent: RestContentState

    init(model: CurfewAppModel, display: RestDisplayPresentation) {
        self.model = model
        self.display = display
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

    private var clockDesign: Font.Design {
        switch model.restAppearance.clockStyle {
        case .rounded: .rounded
        case .standard: .default
        case .serif: .serif
        }
    }

    var sceneSnapshot: RestSceneSnapshot {
        let interval = model.reflectionState.scheduledInterval
        let candidate = interval?.end ?? model.state.unlockDate
        let unlock = candidate == .distantFuture ? nil : candidate
        return RestSceneSnapshot(
            version: 1,
            expiresAt: unlock?.addingTimeInterval(3600) ?? model.currentTime
                .addingTimeInterval(300),
            appearance: model.restAppearance,
            lockDate: interval?.start ?? model.state.lockDate,
            unlockDate: unlock
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TimelineView(.animation(
                    minimumInterval: reduceMotion || model.restAppearance
                        .staticBackground ? 1 : 1.0 / 24,
                    paused: !display.isVisible
                )) { context in
                    RestAmbientScene(
                        snapshot: sceneSnapshot,
                        date: model.isDemoSession ? model.currentTime : context.date,
                        image: backgroundImage,
                        reduceMotion: reduceMotion,
                        reduceTransparency: reduceTransparency,
                        showsClock: false
                    )
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
                ScrollView {
                    VStack(spacing: content == .quiet ? 24 : 18) {
                        Spacer(minLength: content == .quiet ? 48 : 0)
                        Text(model.currentTime, style: .time)
                            .font(.system(
                                size: content == .quiet ? 110 : 64,
                                weight: .semibold,
                                design: clockDesign
                            ))
                            .monospacedDigit()
                            .foregroundStyle(SundownPalette.warmWhite)
                            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
                            .accessibilityIdentifier("rest-clock")
                        if !model.restAppearance.message.isEmpty {
                            Text(model.restAppearance.message)
                                .font(.system(size: 18))
                                .foregroundStyle(SundownPalette.warmWhite)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 600)
                        }
                        Group {
                            if content == .morning, !model.isEnforcingLockout {
                                DaybreakReflectionView()
                            } else {
                                LockoutScreenView(
                                    message: model.lockoutMessage,
                                    contentDelay: choreography.contentDelay
                                )
                            }
                        }
                        .transition(.opacity.combined(with: .offset(y: motion.translation)))
                        .animation(
                            .easeOut(duration: motion.contentDuration)
                                .delay(choreography.contentDelay), value: content
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .animation(
                        .easeInOut(duration: motion.layoutDuration)
                            .delay(choreography.layoutDelay), value: content
                    )
                }
                .scrollIndicators(.hidden)
                .environment(model)
                .allowsHitTesting(display.isVisible && coverOpacity == 0)

                Color.black.opacity(display.isVisible ? coverOpacity : 1)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
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
            guard display.revealGeneration > 0, display.isVisible else { return }
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
}
