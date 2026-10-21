#if DEBUG
    import CurfewKit
    import Foundation

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

        /// A finite synthetic clock for typing-through-midnight acceptance.
        /// It is enabled only by this named unsigned Debug fixture.
        func playDemoRestClock() {
            guard isDemoSession, DemoReviewState.current == .restContinuity else { return }
            Task { @MainActor [weak self] in
                for _ in 0 ..< 20 {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self else { return }
                    let previous = currentTime
                    currentTime = currentTime.addingTimeInterval(1)
                    if !Calendar.current.isDate(previous, inSameDayAs: currentTime) {
                        resetReflectionGatesForNewDay()
                    }
                    overlayCoordinator.updateOverlays(
                        for: state, model: self, lockoutMessage: lockoutMessage
                    )
                }
            }
        }
    }
#endif
