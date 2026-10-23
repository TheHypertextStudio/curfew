import AppKit
import CurfewAtmosphere
import CurfewKit
import Observation

@Observable
@MainActor
final class RestHandoffRuntime {
    var coordinator: RestHandoffCoordinator?
    @ObservationIgnored var launcher: RestSaverLauncher?
    @ObservationIgnored var visibleHosts: Set<UUID> = []
    @ObservationIgnored var occurrence: Date?
    @ObservationIgnored var blockers: [RestHandoffPolicy.Blocker] = []
    @ObservationIgnored var lastInput: TimeInterval = 0
    var sessionIsActive = true
}

@MainActor
extension CurfewAppModel {
    var restHandoffIsAmbient: Bool {
        guard let phase = restRuntime.handoff.coordinator?.policy.phase else { return false }
        return phase != .interactive
    }

    var canRestNow: Bool {
        restPresentation.layout == .quiet && !isOverrideComposerVisible && !restHandoffIsAmbient
    }

    func restNow() {
        guard canRestNow, !isDemoSession else { return }
        updateRestHandoff()
        guard let coordinator = restRuntime.handoff.coordinator else {
            openRestScreenSetup()
            return
        }
        coordinator.handle(.restNow)
    }

    func openRestScreenSetup() {
        settingsDestination = .restScreen
        openSettings()
    }

    func configureRestHandoff(preferences: RestScreenSaverPreferences) {
        let runtime = restRuntime.handoff
        let launcher = RestSaverLauncher.live(preferences: preferences)
        runtime.launcher = launcher
        runtime.coordinator = RestHandoffCoordinator(operations: .init(
            settle: {
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                let motion = RestAppearance.standard.motion(reduceMotion: reduceMotion)
                try await Task.sleep(for: .seconds(motion.contentDuration + motion.layoutDuration))
            },
            launch: { [weak self] in
                // Check for input once more at the end of the visual transition.
                self?.updateRestHandoff()
                return await launcher.launch()
            },
            refreshTime: { [weak self] in self?.currentTime = Date() },
            refreshAuthority: { [weak self] in
                guard let self else { return }
                // Existing authority path preserves stronger/durable restrictions.
                // The handoff neither grants release nor arms a disarmed model.
                if isEnforcementRunning {
                    tick()
                } else {
                    displayTick()
                }
                _ = reassertEnforcementIfNeeded()
            }
        ), uptime: { ProcessInfo.processInfo.systemUptime })
    }

    /// Called by the existing model clock, never a new polling owner or event tap.
    func updateRestHandoff() {
        let runtime = restRuntime.handoff
        guard restRuntime.configured, !isDemoSession,
              !RuntimeEnvironment.hasLoadedTestRuntime,
              let coordinator = runtime.coordinator else { return }
        if runtime.launcher?.hasReturned == true, runtime.sessionIsActive {
            coordinator.handle(.saverReturned)
        }
        guard !runtime.visibleHosts.isEmpty else {
            if coordinator.policy.phase == .interactive {
                coordinator.reset()
            }
            return
        }
        let occurrence = reflectionState.scheduledInterval?.start
        if runtime.occurrence != occurrence, coordinator.policy.phase == .interactive {
            coordinator.reset()
            runtime.blockers = []
            runtime.occurrence = occurrence
        }
        let idle = CGEventSourceIdleSource().secondsSinceLastInput()
        let latestInput = ProcessInfo.processInfo.systemUptime - idle
        if latestInput.isFinite, latestInput > runtime.lastInput + 0.05 {
            runtime.lastInput = latestInput
            coordinator.handle(.input)
        }
        let form = restPresentation.layout != .quiet
        let modal = NSApp.modalWindow != nil || NSApp.windows.contains {
            $0.isVisible && $0.attachedSheet != nil
        }
        for (blocker, active) in [
            (RestHandoffPolicy.Blocker.editing, form),
            (.confirmation, isOverrideComposerVisible), (.recovery, modal)
        ] where runtime.blockers.contains(blocker) != active {
            if active {
                runtime.blockers.append(blocker)
            } else {
                runtime.blockers.removeAll { $0 == blocker }
            }
            coordinator.handle(.setBlocker(blocker, active: active))
        }
        if !form {
            coordinator.handle(.reflectionResolved(.skipped))
        }
        coordinator.handle(.idleCheck)
    }
}
