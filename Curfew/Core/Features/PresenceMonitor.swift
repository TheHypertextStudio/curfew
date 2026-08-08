import Foundation

/// Why a camera session ended. Recorded on `presence.camera_stopped` so the
/// audit log bounds every window the camera was on *and* says what closed it.
enum CameraStopReason: String {
    /// The user turned presence detection off.
    case settingDisabled = "setting_disabled"

    /// Camera access was revoked or restricted while detection was on.
    case authorizationRevoked = "authorization_revoked"

    /// The capture device went away or refused to open — no camera, or
    /// another application holding it exclusively.
    case deviceUnavailable = "device_unavailable"

    /// The app is quitting.
    case appTerminating = "app_terminating"
}

/// Fuses HID idleness with the camera person signal into a single
/// ``PresenceState``, and owns the rule that decides whether the camera runs
/// at all.
///
/// Two jobs, deliberately in one object:
///
/// 1. **Fusion.** Once per tick it crosses `IdleWatcher`'s verdict with the
///    sensor's most recent observation and publishes transitions.
/// 2. **Gating.** It is the only place that calls ``PersonPresenceSensing/start()``,
///    and it calls it only when the user's setting is on *and* macOS says
///    camera access is granted. Every other component reads presence and has
///    no way to switch a camera on.
///
/// Keeping both here means "when is the camera allowed to be live?" has one
/// answer in one file, and that answer is covered by tests that assert the
/// sensor is never started while the setting is off.
///
/// Passive, like ``IdleWatcher``: it owns no timer and does nothing until
/// ``sample(now:cameraEnabled:)`` is called from the tick loop.
final class PresenceMonitor {
    /// The HID side of the fusion. Sampled by the caller, read here — the
    /// tick loop already calls `idleWatcher.sample()` before reaching us, and
    /// double-sampling would fire its transition callback twice.
    private let idleWatcher: IdleWatcher

    /// The camera side. Never started or stopped by anyone else.
    let sensor: any PersonPresenceSensing

    /// Current fused verdict.
    private(set) var state: PresenceState

    /// When ``state`` last changed. The distraction policy measures the
    /// sustained window from here.
    private(set) var stateEnteredAt: Date

    /// The camera signal that fed the current ``state``, after the staleness
    /// check. ``PersonSignal/unavailable`` whenever the camera is off.
    private(set) var personSignal: PersonSignal = .unavailable

    /// Last observed camera authorization, so a change can be detected and
    /// recorded rather than merely reflected.
    private(set) var authorization: CameraAuthorization

    /// Whether the camera is live right now. Drives the in-app indicator.
    var isCameraLive: Bool {
        sensor.isRunning
    }

    /// Whether the monitor currently wants the camera on. Differs from
    /// ``isCameraLive`` only when the device failed to open, which is exactly
    /// the case the Settings panel needs to report.
    private(set) var wantsCamera = false

    /// Fired on every fused-state transition as `(from, to)`.
    var onStateChanged: ((PresenceState, PresenceState) -> Void)?

    /// Fired when the camera actually starts.
    var onCameraStarted: (() -> Void)?

    /// Fired when the camera actually stops, with the best available reason.
    var onCameraStopped: ((CameraStopReason) -> Void)?

    /// Fired when camera authorization changes, as `(from, to)`.
    var onAuthorizationChanged: ((CameraAuthorization, CameraAuthorization) -> Void)?

    /// Last observed liveness, so start/stop are reported once per transition
    /// rather than once per tick.
    private var lastObservedLive = false

    /// Creates a monitor over `idleWatcher` and `sensor`.
    ///
    /// Seeds ``state`` from the world as it is at `now` — with the camera not
    /// yet running, which means an already-idle machine seeds to
    /// ``PresenceState/unknown`` rather than claiming an absence it cannot
    /// see. The first ``sample(now:cameraEnabled:)`` then reports a real
    /// transition if the camera comes up and disagrees.
    init(
        idleWatcher: IdleWatcher,
        sensor: any PersonPresenceSensing,
        now: Date = Date()
    ) {
        self.idleWatcher = idleWatcher
        self.sensor = sensor
        self.authorization = sensor.authorization
        self.state = PresenceFusion.resolve(
            isHIDIdle: idleWatcher.isIdle,
            person: .unavailable
        )
        self.stateEnteredAt = now
    }

    /// One fusion cycle: reconcile the camera against consent, read both
    /// signals, publish any transition.
    ///
    /// - Parameters:
    ///   - now: This tick's clock value.
    ///   - cameraEnabled: The user's `settings.presence.cameraEnabled`. Passed
    ///     in rather than read from a store so the gate is visible at the call
    ///     site and trivially exercised from a test.
    func sample(now: Date, cameraEnabled: Bool) {
        reconcileAuthorization()
        reconcileCamera(enabled: cameraEnabled)
        publishCameraLiveness(enabled: cameraEnabled)

        personSignal = currentPersonSignal(at: now)
        let next = PresenceFusion.resolve(
            isHIDIdle: idleWatcher.isIdle,
            person: personSignal
        )
        guard next != state else { return }
        let previous = state
        state = next
        stateEnteredAt = now
        onStateChanged?(previous, next)
    }

    /// How long the current state has held at `now`.
    func secondsInState(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(stateEnteredAt))
    }

    /// Stops the camera because the app is going away.
    ///
    /// Called from app termination. AVFoundation releases the device when the
    /// process dies anyway, but relying on that would leave a window where a
    /// hung teardown keeps the light on, and the log would have no closing
    /// bracket for the session.
    func shutDown() {
        wantsCamera = false
        guard sensor.isRunning else { return }
        sensor.stop()
        lastObservedLive = false
        onCameraStopped?(.appTerminating)
    }

    /// Asks macOS for camera access and reports the outcome, so the Settings
    /// panel can prompt without reaching past the monitor to the sensor.
    func requestCameraAuthorization(
        completion: @escaping @MainActor (CameraAuthorization) -> Void
    ) {
        sensor.requestAuthorization { [weak self] status in
            self?.reconcileAuthorization()
            completion(status)
        }
    }

    // MARK: - Private

    private func reconcileAuthorization() {
        let current = sensor.authorization
        guard current != authorization else { return }
        let previous = authorization
        authorization = current
        onAuthorizationChanged?(previous, current)
    }

    /// The gate. Both conditions are required, and they are checked here on
    /// every tick rather than once at start-up, so revoking camera access in
    /// System Settings takes the camera down within a second without the user
    /// having to relaunch Curfew.
    private func reconcileCamera(enabled: Bool) {
        let shouldRun = enabled && authorization.permitsCapture
        guard shouldRun != wantsCamera else { return }
        wantsCamera = shouldRun
        if shouldRun {
            sensor.start()
        } else {
            sensor.stop()
        }
    }

    /// Reports start/stop off *observed* liveness rather than off intent, so a
    /// camera that failed to open is recorded as having stopped instead of
    /// being reported as running forever.
    private func publishCameraLiveness(enabled: Bool) {
        let live = sensor.isRunning
        guard live != lastObservedLive else { return }
        lastObservedLive = live
        if live {
            onCameraStarted?()
        } else {
            onCameraStopped?(stopReason(enabled: enabled))
        }
    }

    private func stopReason(enabled: Bool) -> CameraStopReason {
        if !enabled {
            return .settingDisabled
        }
        if !authorization.permitsCapture {
            return .authorizationRevoked
        }
        // The user still wants it and macOS still permits it, so the camera
        // itself is what went away.
        return .deviceUnavailable
    }

    /// The camera verdict, or ``PersonSignal/unavailable``.
    ///
    /// Two independent reasons to distrust a reading, both of which must
    /// produce "no signal" rather than "nobody there": the camera is not
    /// running, or the last frame is older than the tolerance because the
    /// session wedged.
    private func currentPersonSignal(at now: Date) -> PersonSignal {
        guard sensor.isRunning else { return .unavailable }
        return sensor.latestObservation.signal(
            at: now,
            tolerance: PresenceDetectionPolicy.observationToleranceSeconds
        )
    }
}
