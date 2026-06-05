import AppKit
@testable import Curfew
import Foundation

/// Minimal `AppRouting` spy that records call counts. Shared across test
/// files so every behaviour test can inject the same stand-in without each
/// file redefining its own.
///
/// Kept at module-internal visibility (default) rather than `private`
/// because multiple test files need it; `private` would scope it to one
/// file only, which is why the pre-split test file could embed it.
@MainActor
final class AppRouterSpy: AppRouting {
    /// Number of times `activate()` has been called.
    private(set) var activateCallCount = 0

    /// Number of times `showSettings()` has been called.
    private(set) var showSettingsCallCount = 0

    func activate() {
        activateCallCount += 1
    }

    func showSettings() {
        showSettingsCallCount += 1
    }
}

/// Minimal `GettingStartedPresenting` spy that records present/dismiss
/// calls. Shared across test files for the same reason as `AppRouterSpy`.
@MainActor
final class GettingStartedPresenterSpy: GettingStartedPresenting {
    /// Number of times `present(model:)` has been called.
    private(set) var presentCallCount = 0

    /// Number of times `dismiss()` has been called.
    private(set) var dismissCallCount = 0

    func present(model: CurfewAppModel) {
        presentCallCount += 1
    }

    func dismiss() {
        dismissCallCount += 1
    }
}

/// `RespawnGuardControlling` spy that records install / arm / disarm
/// invocations so tests can assert the model wires the user-space respawn
/// deterrent at the expected lifecycle points without touching real
/// `launchctl` state.
final class RecordingRespawnGuard: RespawnGuardControlling {
    /// Ordered method-name log, e.g. `["install", "arm", "disarm"]`.
    private(set) var callLog: [String] = []
    /// Optional error each subsequent `install` call should throw. When
    /// non-empty, the head of the queue is dequeued; empty means succeed.
    var installErrors: [Error] = []

    /// Default init for use in test scopes; `nonisolated` to mirror the
    /// pattern used by other test spies that can be constructed off-actor.
    init() {}

    func install() throws {
        callLog.append("install")
        guard !installErrors.isEmpty else { return }
        throw installErrors.removeFirst()
    }

    func uninstall() throws {
        callLog.append("uninstall")
    }

    func arm() throws {
        callLog.append("arm")
    }

    func disarm() throws {
        callLog.append("disarm")
    }
}

/// `ShutdownControlling` spy for driving `ShutdownWorkflow` through its
/// state machine without telling macOS to actually shut down.
///
/// `results` is a FIFO queue of outcomes for `executeShutdown()`. Each call
/// dequeues and returns the next value; when empty, returns `.failed`.
/// `callLog` records `"graceful"` / `"shutdown"` entries in call order so
/// tests asserting ordering (graceful-terminate-before-shutdown) can check
/// the sequence cheaply. Tests that don't care about ordering simply
/// ignore `callLog`.
final class ShutdownControllerSpy: ShutdownControlling {
    /// Ordered log of method names, e.g. `["graceful", "shutdown"]`.
    private(set) var callLog: [String] = []

    private var results: [ShutdownExecutionOutcome]

    init(results: [Bool]) {
        self.results = results.map { $0 ? .succeeded : .failed }
    }

    init(outcomes: [ShutdownExecutionOutcome]) {
        self.results = outcomes
    }

    func requestGracefulTermination() {
        callLog.append("graceful")
    }

    func executeShutdown() -> ShutdownExecutionOutcome {
        callLog.append("shutdown")
        guard !results.isEmpty else {
            return .failed
        }
        return results.removeFirst()
    }
}

/// Scriptable `AccessibilityAuthorizing` fake for exercising model logic that
/// gates on Accessibility trust without triggering a real macOS AX prompt.
///
/// The real `AXIsProcessTrusted` C symbols cannot be driven headlessly, so this
/// fake stands in for them: `trusted` is the value `isTrusted()` returns, and
/// `promptResult` is what `promptForTrust()` returns. Both calls are counted so
/// tests can assert they were (or were not) invoked.
final class FakeAccessibilityAuthorization: AccessibilityAuthorizing {
    /// Scripted return value for `isTrusted()`.
    var trusted: Bool

    /// Scripted return value for `promptForTrust()`.
    var promptResult: Bool

    /// Number of times `isTrusted()` has been called.
    private(set) var isTrustedCallCount = 0

    /// Number of times `promptForTrust()` has been called.
    private(set) var promptForTrustCallCount = 0

    /// Creates a fake with the given scripted trust and prompt outcomes.
    /// - Parameters:
    ///   - trusted: Value returned by `isTrusted()`.
    ///   - promptResult: Value returned by `promptForTrust()`.
    init(trusted: Bool, promptResult: Bool = false) {
        self.trusted = trusted
        self.promptResult = promptResult
    }

    func isTrusted() -> Bool {
        isTrustedCallCount += 1
        return trusted
    }

    @discardableResult
    func promptForTrust() -> Bool {
        promptForTrustCallCount += 1
        return promptResult
    }
}
