@testable import Curfew
import Foundation
import Testing

/// `PresenceMonitor` behaviour, with the enabled/disabled gate first.
///
/// The gating tests are the load-bearing ones. Everything else in the presence
/// feature is a matter of accuracy; whether the camera runs when the user said
/// it should not is a matter of trust, so it gets asserted from several angles:
/// the setting off, access not granted, access revoked mid-session, and the
/// app quitting.
@MainActor
struct PresenceMonitorTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// A monitor over a settable idle source and a fake sensor.
    ///
    /// The watcher comes back alongside the source because `PresenceMonitor`
    /// deliberately does not sample it — the tick loop does that first, and
    /// double-sampling would fire the watcher's own transition callback twice.
    /// Tests that move the idle needle therefore call `watcher.sample()` in the
    /// same order the tick loop does.
    private func makeMonitor(
        idleSeconds: TimeInterval,
        authorization: CameraAuthorization = .authorized
    ) -> (
        monitor: PresenceMonitor,
        sensor: FakePresenceSensor,
        idle: MutableIdleSource,
        watcher: IdleWatcher
    ) {
        let source = MutableIdleSource(seconds: idleSeconds)
        let watcher = IdleWatcher(source: source, idleThresholdSeconds: 300)
        let sensor = FakePresenceSensor(authorization: authorization)
        let monitor = PresenceMonitor(idleWatcher: watcher, sensor: sensor, now: epoch)
        return (monitor, sensor, source, watcher)
    }

    // MARK: - Gating

    @Test("A disabled camera is never started, however many ticks run")
    func disabledCameraNeverStarts() {
        let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600)

        for tick in 0 ..< 50 {
            monitor.sample(
                now: epoch.addingTimeInterval(TimeInterval(tick)),
                cameraEnabled: false
            )
        }

        #expect(sensor.startCount == 0)
        #expect(!sensor.isRunning)
        #expect(!monitor.isCameraLive)
        #expect(!monitor.wantsCamera)
        // And the fused verdict is honest about it rather than guessing.
        #expect(monitor.state == .unknown)
        #expect(monitor.personSignal == .unavailable)
    }

    @Test("An enabled camera is not started without granted access")
    func unauthorizedCameraNeverStarts() {
        for status in [CameraAuthorization.notDetermined, .denied, .restricted] {
            let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600, authorization: status)
            monitor.sample(now: epoch, cameraEnabled: true)
            #expect(sensor.startCount == 0, "started the camera with \(status.rawValue) access")
            #expect(monitor.state == .unknown)
        }
    }

    @Test("Enabling the setting with access granted starts the camera exactly once")
    func enabledCameraStartsOnce() {
        let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600)

        for tick in 0 ..< 10 {
            monitor.sample(
                now: epoch.addingTimeInterval(TimeInterval(tick)),
                cameraEnabled: true
            )
        }

        #expect(sensor.startCount == 1)
        #expect(monitor.isCameraLive)
    }

    @Test("Turning the setting off stops the camera on the next sample")
    func disablingStopsTheCamera() {
        let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600)
        var stopReasons: [CameraStopReason] = []
        monitor.onCameraStopped = { stopReasons.append($0) }

        monitor.sample(now: epoch, cameraEnabled: true)
        #expect(sensor.isRunning)

        monitor.sample(now: epoch.addingTimeInterval(1), cameraEnabled: false)

        #expect(!sensor.isRunning)
        #expect(sensor.stopCount == 1)
        #expect(stopReasons == [.settingDisabled])
        #expect(monitor.state == .unknown)
    }

    @Test("Revoking camera access mid-session takes the camera down")
    func revokedAuthorizationStopsTheCamera() {
        let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600)
        var stopReasons: [CameraStopReason] = []
        var authorizationMoves: [String] = []
        monitor.onCameraStopped = { stopReasons.append($0) }
        monitor.onAuthorizationChanged = { from, to in
            authorizationMoves.append("\(from.rawValue)->\(to.rawValue)")
        }

        monitor.sample(now: epoch, cameraEnabled: true)
        #expect(sensor.isRunning)

        // The user revokes access in System Settings while Curfew runs. The
        // setting is still on, so only the per-tick recheck catches this.
        sensor.authorization = .denied
        monitor.sample(now: epoch.addingTimeInterval(1), cameraEnabled: true)

        #expect(!sensor.isRunning)
        #expect(stopReasons == [.authorizationRevoked])
        #expect(authorizationMoves == ["authorized->denied"])
    }

    @Test("Quitting stops the camera and records the reason")
    func shutDownStopsTheCamera() {
        let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600)
        var stopReasons: [CameraStopReason] = []

        monitor.sample(now: epoch, cameraEnabled: true)
        monitor.onCameraStopped = { stopReasons.append($0) }
        monitor.shutDown()

        #expect(!sensor.isRunning)
        #expect(stopReasons == [.appTerminating])
        #expect(!monitor.wantsCamera)
    }

    @Test("A camera that will not open is reported as stalled, not as running")
    func failedOpenIsReportedHonestly() {
        let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600)
        sensor.failsToOpen = true
        var stopReasons: [CameraStopReason] = []
        monitor.onCameraStopped = { stopReasons.append($0) }

        monitor.sample(now: epoch, cameraEnabled: true)

        #expect(sensor.startCount == 1)
        #expect(!monitor.isCameraLive)
        #expect(monitor.wantsCamera)
        #expect(stopReasons.isEmpty, "never went live, so there was no stop to report")
        #expect(monitor.state == .unknown)
    }

    // MARK: - Fusion through the monitor

    @Test("Idle with a person in frame reports present-but-idle")
    func presentButIdleIsReported() {
        let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600)
        var transitions: [String] = []
        monitor.onStateChanged = { from, to in
            transitions.append("\(from.rawValue)->\(to.rawValue)")
        }

        monitor.sample(now: epoch, cameraEnabled: true)
        sensor.observe(.detected, at: epoch.addingTimeInterval(1))
        monitor.sample(now: epoch.addingTimeInterval(2), cameraEnabled: true)

        #expect(monitor.state == .presentButIdle)
        #expect(transitions == ["unknown->present_idle"])
        #expect(monitor.stateEnteredAt == epoch.addingTimeInterval(2))
    }

    @Test("Idle with an empty frame reports absent")
    func absentIsReported() {
        let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600)

        monitor.sample(now: epoch, cameraEnabled: true)
        sensor.observe(.notDetected, at: epoch.addingTimeInterval(1))
        monitor.sample(now: epoch.addingTimeInterval(2), cameraEnabled: true)

        #expect(monitor.state == .absent)
    }

    @Test("Input arriving while the camera sees nobody still reports working")
    func inputBeatsAnEmptyFrame() {
        let (monitor, sensor, idle, watcher) = makeMonitor(idleSeconds: 600)

        monitor.sample(now: epoch, cameraEnabled: true)
        sensor.observe(.notDetected, at: epoch.addingTimeInterval(1))
        // The user is typing on an external keyboard, out of the lens' cone.
        idle.seconds = 2
        watcher.sample()
        monitor.sample(now: epoch.addingTimeInterval(2), cameraEnabled: true)

        #expect(monitor.state == .working)
    }

    @Test("A camera reading that goes stale falls back to unknown, not absent")
    func staleReadingFallsBackToUnknown() {
        let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600)

        monitor.sample(now: epoch, cameraEnabled: true)
        sensor.observe(.detected, at: epoch.addingTimeInterval(1))
        monitor.sample(now: epoch.addingTimeInterval(2), cameraEnabled: true)
        #expect(monitor.state == .presentButIdle)

        // No further frames — the capture session wedged. Past the tolerance
        // the verdict must decay to "cannot tell", not flip to "gone".
        let later = epoch.addingTimeInterval(
            2 + PresenceDetectionPolicy.observationToleranceSeconds + 5
        )
        monitor.sample(now: later, cameraEnabled: true)

        #expect(monitor.state == .unknown)
        #expect(monitor.personSignal == .unavailable)
    }

    @Test("Transitions fire once per change, not once per tick")
    func transitionsAreDeduplicated() {
        let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600)
        var changes = 0
        monitor.onStateChanged = { _, _ in changes += 1 }

        monitor.sample(now: epoch, cameraEnabled: true)
        for tick in 1 ... 10 {
            let now = epoch.addingTimeInterval(TimeInterval(tick))
            sensor.observe(.detected, at: now)
            monitor.sample(now: now, cameraEnabled: true)
        }

        #expect(changes == 1)
    }

    @Test("Time in state is measured from the transition, not from the tick")
    func secondsInStateTracksTheTransition() {
        let (monitor, sensor, _, _) = makeMonitor(idleSeconds: 600)

        monitor.sample(now: epoch, cameraEnabled: true)
        sensor.observe(.detected, at: epoch.addingTimeInterval(1))
        monitor.sample(now: epoch.addingTimeInterval(1), cameraEnabled: true)

        #expect(monitor.secondsInState(at: epoch.addingTimeInterval(181)) == 180)
    }
}
