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
    /// Whether, and to which saver, the lock may hand off right now.
    var decision: RestSaverChoice.Decision = .stay(nil)
    @ObservationIgnored var facts = RestSaverFacts(defaults: .standard)
    @ObservationIgnored var readSelection: () -> RestSaverChoice
        .Selection = RestSaverSelectionReader.live
    @ObservationIgnored var isSaverRunning: () -> Bool = { false }

    var handOffTarget: RestSaverChoice.Target? {
        if case .handOff(let target) = decision {
            return target
        }
        return nil
    }

    /// Re-reads the facts and decides. A proven receipt is remembered.
    func refreshDecision() {
        if launcher?.hasFullScreenReceipt == true {
            facts.curfewSaverProven = true
        }
        let next = RestSaverChoice.decide(
            selection: readSelection(), curfewSaverProven: facts.curfewSaverProven,
            usesSelectedSaver: facts.usesSelectedSaver, saverRunning: isSaverRunning()
        )
        if next != decision {
            decision = next
        }
    }

    @discardableResult
    func observeReturn() -> Task<Void, Never>? {
        guard sessionIsActive, launcher?.consumeReturn() == true else { return nil }
        return coordinator?.handle(.saverReturned)
    }
}

@MainActor
extension CurfewAppModel {
    var restHandoffIsAmbient: Bool {
        guard let phase = restRuntime.handoff.coordinator?.policy.phase else { return false }
        return phase != .interactive
    }

    /// "Start the screen saver" is offered only when a handoff is allowed.
    var canRestNow: Bool {
        restPresentation.layout == .quiet && !isOverrideComposerVisible && !restHandoffIsAmbient
            && restRuntime.handoff.handOffTarget != nil
    }

    /// What is missing before Curfew can hand off, when it can be set up.
    var restSaverMissing: RestSaverChoice.Missing? {
        if case .stay(let missing) = restRuntime.handoff.decision {
            return missing
        }
        return nil
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
        guard !isEnforcingLockout else { return }
        settingsDestination = .restScreen
        openSettings()
    }

    func configureRestHandoff(preferences: RestScreenSaverPreferences) {
        let runtime = restRuntime.handoff
        let launcher = RestSaverLauncher.live(preferences: preferences)
        runtime.launcher = launcher
        runtime.isSaverRunning = {
            !NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.ScreenSaver.Engine"
            ).isEmpty && launcher.ownedProcess == nil
        }
        runtime.coordinator = RestHandoffCoordinator(operations: .init(
            settle: {
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                let motion = RestAppearance.standard.motion(reduceMotion: reduceMotion)
                try await Task.sleep(for: .seconds(motion.contentDuration + motion.layoutDuration))
            },
            launch: { [weak self] in
                // Check for input once more at the end of the visual transition.
                self?.updateRestHandoff()
                guard let target = self?.restRuntime.handoff.handOffTarget else {
                    return .saverAlreadyRunning
                }
                return await launcher.launch(target: target)
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
        runtime.observeReturn()
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
        // Only hand off when the rule allows it: Curfew's proven saver, or
        // the selected saver by the person's choice, and never over a saver
        // that is already running.
        runtime.refreshDecision()
        guard runtime.handOffTarget != nil else { return }
        coordinator.handle(.idleCheck)
    }
}
