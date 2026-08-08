import AppKit
import Foundation

/// Per-model presence runtime, keyed by model identity.
///
/// File-scoped rather than stored on `CurfewAppModel` — the same pattern
/// `CurfewAppModel+Audit.swift` and `CurfewAppModel+EnforcementHealth.swift`
/// use — because the model class sits at its lint-enforced line budget. Every
/// access is `@MainActor`, so the dictionary needs no lock.
private struct PresenceRuntime {
    /// The fusion + gating object. Created lazily on first use so a model that
    /// never ticks (previews, fixtures, half the test suite) never constructs
    /// a capture sensor at all.
    var monitor: PresenceMonitor

    /// When the last distraction nudge went out. ``Date/distantPast`` until
    /// one has, so the repeat-window arithmetic needs no optional.
    var lastWarnedAt: Date = .distantPast
}

private var presenceRuntimes: [ObjectIdentifier: PresenceRuntime] = [:]

/// Test seam: a sensor to build the monitor around instead of the real
/// camera-backed one. Assigned before the first ``CurfewAppModel/presenceMonitor``
/// access. Entries are not reaped on deinit; production leaves this empty.
private var presenceSensorOverrides: [ObjectIdentifier: any PersonPresenceSensing] = [:]

/// Presence detection wiring for `CurfewAppModel`.
///
/// Three responsibilities, in tick order:
///
/// 1. ``samplePresence()`` — reconcile the camera against the user's consent,
///    fuse HID idleness with the camera signal, publish the result.
/// 2. ``evaluateDistractionWarning()`` — decide whether a present-but-idle
///    user gets a nudge, and deliver it.
/// 3. The audit emitters — record every transition, and never a frame.
///
/// The privacy-relevant invariant lives in ``samplePresence()``: the only
/// argument that can put the camera into a running state is
/// `settings.presence.cameraEnabled`, and nothing else in the app calls
/// `PersonPresenceSensing.start()`.
@MainActor
extension CurfewAppModel {
    /// The presence monitor for this model, created and wired on first access.
    ///
    /// Constructing the production sensor does **not** open the camera —
    /// `VisionCameraPresenceSensor.start()` is the only thing that does, and
    /// `PresenceMonitor` calls it only behind the consent gate.
    var presenceMonitor: PresenceMonitor {
        let identity = ObjectIdentifier(self)
        if let runtime = presenceRuntimes[identity] {
            return runtime.monitor
        }
        let sensor = presenceSensorOverrides[identity] ?? VisionCameraPresenceSensor()
        let monitor = PresenceMonitor(
            idleWatcher: idleWatcher,
            sensor: sensor,
            now: currentTime
        )
        presenceRuntimes[identity] = PresenceRuntime(monitor: monitor)
        wirePresenceCallbacks(monitor)
        return monitor
    }

    /// Test seam. Assigning a sensor here builds this model's monitor around
    /// it, so a suite can drive presence without a camera.
    var presenceSensorOverride: (any PersonPresenceSensing)? {
        get { presenceSensorOverrides[ObjectIdentifier(self)] }
        set { presenceSensorOverrides[ObjectIdentifier(self)] = newValue }
    }

    // MARK: - Published-equivalent reads

    // These deliberately read the runtime dictionary instead of calling
    // `presenceMonitor`, so rendering a view never constructs a sensor. A
    // model that has not ticked reports the honest default: nothing known,
    // camera off.

    /// The fused presence verdict. ``PresenceState/unknown`` before the first
    /// sample, which is also the steady state on a default install.
    var presenceState: PresenceState {
        presenceRuntimes[ObjectIdentifier(self)]?.monitor.state ?? .unknown
    }

    /// The camera's contribution to the current verdict, after the staleness
    /// check. ``PersonSignal/unavailable`` whenever the camera is off — which
    /// is what a default install reports forever.
    var presenceSignal: PersonSignal {
        presenceRuntimes[ObjectIdentifier(self)]?.monitor.personSignal ?? .unavailable
    }

    /// Whether the camera is on right now. Drives the in-app indicator, which
    /// must never claim the camera is off while a session is live.
    var isPresenceCameraLive: Bool {
        presenceRuntimes[ObjectIdentifier(self)]?.monitor.isCameraLive ?? false
    }

    /// Whether Curfew wants the camera on but does not have it — access
    /// granted and the setting on, yet no session. Surfaced in Settings so a
    /// broken camera does not look like working presence detection.
    var isPresenceCameraStalled: Bool {
        guard let monitor = presenceRuntimes[ObjectIdentifier(self)]?.monitor else {
            return false
        }
        return monitor.wantsCamera && !monitor.isCameraLive
    }

    /// Live camera authorization, read straight from the sensor so a change
    /// made in System Settings shows without a relaunch. Falls back to the
    /// process-wide status when no monitor exists yet.
    var presenceCameraAuthorization: CameraAuthorization {
        guard let monitor = presenceRuntimes[ObjectIdentifier(self)]?.monitor else {
            return VisionCameraPresenceSensor.currentAuthorization
        }
        return monitor.authorization
    }

    // MARK: - Tick

    /// One presence cycle. Called from `tick()` immediately after
    /// `idleWatcher.sample()` so both halves of the fusion describe the same
    /// instant.
    ///
    /// The camera gate is this one call: `cameraEnabled` comes from the user's
    /// persisted setting, which defaults to `false` and which only the
    /// Settings window can change. Turning the setting off here takes the
    /// camera down on the next tick — within a second — rather than at the
    /// next launch.
    func samplePresence() {
        presenceMonitor.sample(
            now: currentTime,
            cameraEnabled: settings.presence.cameraEnabled
        )
    }

    /// Decides whether to nudge a present-but-idle user, and does it.
    ///
    /// Delivery is a notification rather than an overlay on purpose: the state
    /// this fires in is one where the user is *at* the machine but not using
    /// it, and something that seizes the screen would interrupt the reading or
    /// the call that Curfew cannot distinguish from drift.
    func evaluateDistractionWarning() {
        let identity = ObjectIdentifier(self)
        guard let runtime = presenceRuntimes[identity] else { return }
        let presence = settings.presence
        let verdict = presence.distractionPolicy.decide(
            state: runtime.monitor.state,
            phase: state.phase,
            stateEnteredAt: runtime.monitor.stateEnteredAt,
            lastWarnedAt: runtime.lastWarnedAt,
            now: currentTime,
            // Both switches, folded here rather than inside the policy: the
            // camera being off means the fused state is `.unknown` anyway, but
            // stating the dependency at the call site keeps "no camera, no
            // nudge" true by construction rather than by consequence.
            isEnabled: presence.cameraEnabled && presence.warnsWhenDistracted
        )
        guard verdict.isWarn else { return }

        let sustained = runtime.monitor.secondsInState(at: currentTime)
        presenceRuntimes[identity]?.lastWarnedAt = currentTime
        notificationManager.deliverDistractionNudge()
        recordAuditDistractionWarning(sustainedSeconds: sustained)
    }

    /// Stops the camera on quit and records the closing bracket.
    func shutDownPresence() {
        guard let runtime = presenceRuntimes[ObjectIdentifier(self)] else { return }
        runtime.monitor.shutDown()
    }

    /// Prompts for camera access, then persists the user's choice to turn
    /// presence detection on only if it was actually granted.
    ///
    /// The order matters. Flipping the setting first and prompting second
    /// would leave a persisted `cameraEnabled: true` on a machine where access
    /// was refused — a stored intent to run a camera the user just declined.
    func enablePresenceDetection() {
        presenceMonitor.requestCameraAuthorization { [weak self] status in
            guard let self else { return }
            objectWillChange.send()
            guard status.permitsCapture else { return }
            settings.presence.cameraEnabled = true
        }
    }

    /// Opens the Camera pane of System Settings.
    ///
    /// The only remediation available once access has been denied: macOS will
    /// not re-prompt, so Curfew has to hand the user to the switch rather than
    /// ask again. Guarded against the unit-test host so a suite never opens
    /// System Settings on the developer's desktop.
    func openCameraPrivacySettings() {
        guard !RuntimeEnvironment.isUnitTestHost else { return }
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Turns presence detection off and takes the camera down immediately.
    ///
    /// Does not wait for the next tick: the user asked for the camera to stop,
    /// and a second of green light after that request is a second too long.
    func disablePresenceDetection() {
        settings.presence.cameraEnabled = false
        presenceMonitor.sample(now: currentTime, cameraEnabled: false)
    }

    // MARK: - Wiring

    private func wirePresenceCallbacks(_ monitor: PresenceMonitor) {
        monitor.onStateChanged = { [weak self] _, _ in
            // The presence reads above are computed, not `@Published`, so the
            // change has to be announced by hand for SwiftUI to see it.
            self?.objectWillChange.send()
        }
        monitor.onCameraStarted = { [weak self] in
            self?.objectWillChange.send()
            self?.recordAuditCameraStarted()
        }
        monitor.onCameraStopped = { [weak self] reason in
            self?.objectWillChange.send()
            self?.recordAuditCameraStopped(reason)
        }
        monitor.onAuthorizationChanged = { [weak self] from, to in
            self?.objectWillChange.send()
            self?.recordAuditCameraAuthorization(from: from, to: to)
        }
    }
}
