@testable import Curfew
import Foundation

/// An `IdleTimeSource` whose reported idle duration the test sets directly.
///
/// Shared by every presence suite so the HID half of the fusion can be moved
/// across the threshold without waiting real seconds.
final class MutableIdleSource: IdleTimeSource {
    /// Seconds since the last input, as this source will report it.
    var seconds: TimeInterval

    /// Creates a source reporting `seconds`.
    init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    /// The value the test last set.
    func secondsSinceLastInput() -> TimeInterval {
        seconds
    }
}

/// A ``PersonPresenceSensing`` that opens nothing.
///
/// The point of this fake is not only convenience. Every presence test depends
/// on it, and it counts ``startCount`` — so a regression that started the
/// camera behind a disabled setting shows up as a failed count assertion
/// rather than as a green light on someone's Mac.
@MainActor
final class FakePresenceSensor: PersonPresenceSensing {
    /// Authorization this fake reports. Settable so a test can revoke access
    /// mid-run.
    var authorization: CameraAuthorization

    /// Whether the fake considers itself running.
    private(set) var isRunning = false

    /// The observation the fake hands back.
    var latestObservation: PersonObservation = .never

    /// How many times ``start()`` has been called. The gating assertions read
    /// this: for a disabled camera it must stay at zero.
    private(set) var startCount = 0

    /// How many times ``stop()`` has been called.
    private(set) var stopCount = 0

    /// How many times ``requestAuthorization(completion:)`` has been called.
    private(set) var authorizationRequestCount = 0

    /// Status the fake reports back from an authorization request. Defaults to
    /// the current ``authorization``.
    var authorizationRequestResult: CameraAuthorization?

    /// When `true`, ``start()`` records the call but leaves ``isRunning``
    /// false — the "camera is authorized but the device will not open" case.
    var failsToOpen = false

    /// Creates a fake with the given starting authorization.
    init(authorization: CameraAuthorization = .authorized) {
        self.authorization = authorization
    }

    /// Records the call and, unless ``failsToOpen``, goes live.
    func start() {
        startCount += 1
        isRunning = !failsToOpen
    }

    /// Goes dark and drops the last observation, exactly as the real sensor
    /// does — a stale verdict must not outlive its session.
    func stop() {
        stopCount += 1
        isRunning = false
        latestObservation = .never
    }

    /// Reports ``authorizationRequestResult`` (or the current status)
    /// synchronously, so tests need no expectation plumbing.
    func requestAuthorization(
        completion: @escaping @MainActor (CameraAuthorization) -> Void
    ) {
        authorizationRequestCount += 1
        if let authorizationRequestResult {
            authorization = authorizationRequestResult
        }
        completion(authorization)
    }

    /// Convenience for "the camera saw a person just now".
    func observe(_ signal: PersonSignal, at moment: Date) {
        latestObservation = PersonObservation(signal: signal, timestamp: moment)
    }
}
