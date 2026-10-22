#if DEBUG
    import CurfewKit
    import Foundation
    import SwiftUI

    struct DemoRestClock {
        let wallStart: Date
        let sceneStart: Date
    }

    @MainActor
    extension CurfewAppModel {
        /// Isolated rest scenes. This never runs the enforcement tick, requests
        /// system permissions, or changes physical display power.
        func applyDemoRestState(_ review: DemoReviewState) {
            guard isDemoSession else { return }
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: currentTime)
            let lock = midnight.addingTimeInterval(22 * 3600)
            let unlock = lock.addingTimeInterval(9 * 3600)
            let isMorning = review == .restMorning
            currentTime = isMorning ? unlock.addingTimeInterval(60)
                : midnight.addingTimeInterval(24 * 3600 - 2)
            reflectionState.demoRestClock = review == .restContrastControl ? nil : DemoRestClock(
                wallStart: Date(),
                sceneStart: currentTime
            )
            reflectionState.eveningLockDate = lock
            reflectionState.scheduledInterval = DateInterval(start: lock, end: unlock)
            state = CurfewEvaluation(
                phase: isMorning ? .working : .locked, warningStage: .none,
                minutesRemaining: 0, canRequestExtension: false,
                lockDate: lock, unlockDate: unlock
            )
            reflectionState.isEveningReflectionPending = review == .restContinuity
            reflectionState.isDaybreakPresented = isMorning
            reflectionState.eveningDraft = ReflectionDraft(prompts: [
                ReflectionPrompt(
                    text: "What would you like to leave here for tomorrow?",
                    kind: .text
                )
            ])
        }

        /// Samples real elapsed time after physical wake, while retaining the
        /// synthetic occurrence and draft. This never polls or starts enforcement.
        func refreshDemoRestClock(at now: Date = Date()) {
            guard isDemoSession, let clock = reflectionState.demoRestClock else { return }
            let previous = currentTime
            currentTime = clock.sceneStart.addingTimeInterval(max(
                0,
                now.timeIntervalSince(clock.wallStart)
            ))
            if !Calendar.current.isDate(previous, inSameDayAs: currentTime) {
                resetReflectionGatesForNewDay()
            }
            overlayCoordinator.updateOverlays(
                for: state,
                model: self,
                lockoutMessage: lockoutMessage
            )
        }

        /// A finite synthetic clock for typing-through-midnight acceptance.
        /// It is enabled only by this named unsigned Debug fixture.
        func playDemoRestClock() {
            guard isDemoSession,
                  [.restContinuity, .restHold].contains(DemoReviewState.current) else { return }
            let ticks = DemoReviewState.current == .restHold ? 60 : 20
            Task { @MainActor [weak self] in
                for _ in 0 ..< ticks {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self else { return }
                    refreshDemoRestClock()
                }
            }
        }
    }

    /// Temporary control for the isolated native audit; never a shipping scene.
    struct DemoRestContrastControl: View {
        let status: RestRestrictionStatus

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea().accessibilityHidden(true)
                LockoutScreenView.unlockStatusLabel(for: status)
            }
        }
    }
#endif
