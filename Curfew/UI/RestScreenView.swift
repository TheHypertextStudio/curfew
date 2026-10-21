import CurfewKit
import SwiftUI

/// One continuous atmosphere and clock, independent of restriction authority.
/// Content can change without replacing the window, sky, or editing session.
struct RestScreenView: View {
    let model: CurfewAppModel
    @Bindable var display: RestDisplayPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SundownSky(moment: model.restPresentation.sky, isVisible: display.isVisible)
                    .overlay(SundownPalette.textScrim)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                ScrollView {
                    VStack(spacing: content == .quiet ? 24 : 18) {
                        Spacer(minLength: content == .quiet ? 48 : 0)
                        Text(model.currentTime, style: .time)
                            .font(.system(
                                size: content == .quiet ? 110 : 64,
                                weight: .semibold,
                                design: .rounded
                            ))
                            .monospacedDigit()
                            .foregroundStyle(SundownPalette.warmWhite)
                            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
                            .accessibilityIdentifier("rest-clock")
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Curfew rest screen")
        .accessibilityIdentifier("rest-screen")
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
