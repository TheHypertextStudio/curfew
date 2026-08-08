import AppKit
import Foundation
import Security

/// Availability checks for the Apple Events-backed shutdown path.
enum ShutdownSupport {
    static let automationEntitlement = "com.apple.security.automation.apple-events"
    static let automationDeniedErrorCode = -1743

    static var isAvailable: Bool {
        isAvailable(in: .main)
    }

    static func isAvailable(in bundle: Bundle) -> Bool {
        entitlementValue(named: automationEntitlement, in: entitlements(in: bundle))
    }

    static func entitlementValue(named key: String, in entitlements: [String: Any]?) -> Bool {
        switch entitlements?[key] {
        case let value as Bool:
            value
        case let value as NSNumber:
            value.boolValue
        default:
            false
        }
    }

    private static func entitlements(in bundle: Bundle) -> [String: Any]? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            bundle.bundleURL as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard createStatus == errSecSuccess, let staticCode else {
            return nil
        }

        var signingInfo: CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        )
        guard
            copyStatus == errSecSuccess,
            let signingInfo = signingInfo as? [String: Any],
            let entitlements = signingInfo[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        else {
            return nil
        }

        return entitlements
    }
}

enum ShutdownExecutionOutcome: Equatable {
    case succeeded
    case permissionDenied
    case failed
}

/// Abstracts the "ask everyone to quit, then shut down the Mac" pair of
/// operations so tests can drive `ShutdownWorkflow` without actually telling
/// the OS to power off. Production uses `SystemShutdownController`.
protocol ShutdownControlling: AnyObject {
    /// Sends a graceful-terminate request to every running app except Curfew
    /// itself and anything `policy` protects. Apps receive the standard AppKit
    /// "unsaved changes?" flow and may veto termination — that's fine; we
    /// retry with `executeShutdown`.
    func requestGracefulTermination(sparing policy: ProtectedWorkPolicy)

    /// Tells macOS to shut down. Returns a result that distinguishes a normal
    /// failure from the Apple Events permission being denied.
    func executeShutdown() -> ShutdownExecutionOutcome
}

/// Production `ShutdownControlling` that wraps `NSWorkspace` and
/// `NSAppleScript`. Kept as a thin concrete shim so the meaningful logic
/// lives in `ShutdownWorkflow` and is unit-testable.
final class SystemShutdownController: ShutdownControlling {
    static var isAvailable: Bool {
        ShutdownSupport.isAvailable
    }

    /// Terminates every running app except Curfew and anything `policy`
    /// protects, giving the rest the standard "save changes?" opportunity
    /// first.
    ///
    /// The allowlist is the difference between "the Mac went to sleep" and
    /// "the Mac went to sleep and took eight hours of agent work with it":
    /// terminating a terminal emulator kills every child process in it, so a
    /// `claude` or `codex` run started before curfew dies with its window.
    func requestGracefulTermination(sparing policy: ProtectedWorkPolicy) {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let applications = NSWorkspace.shared.runningApplications.filter { app in
            guard app.bundleIdentifier != ownBundleIdentifier else {
                return false
            }
            return !policy.protectsApplication(
                bundleIdentifier: app.bundleIdentifier,
                executableName: app.executableURL?.lastPathComponent
            )
        }
        for application in applications {
            _ = application.terminate()
        }
    }

    /// Executes the system-shutdown AppleScript. The script requires the
    /// `com.apple.security.automation.apple-events` entitlement plus user
    /// approval for System Events scripting — without either, `error` will
    /// be populated and we return a failure result.
    func executeShutdown() -> ShutdownExecutionOutcome {
        guard let script = NSAppleScript(source: "tell application \"System Events\" to shut down")
        else {
            return .failed
        }

        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        guard let error else {
            return .succeeded
        }
        let errorNumber = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        if errorNumber == ShutdownSupport.automationDeniedErrorCode {
            return .permissionDenied
        }
        return .failed
    }
}

/// The three protected-work inputs a shutdown decision needs, bundled so the
/// decision helper takes one argument instead of three positional booleans.
struct ProtectedWorkContext: Equatable {
    /// Allowlist plus the deferral bound.
    var policy: ProtectedWorkPolicy = .default
    /// Whether any unexpired ``ProtectedWorkClaim`` exists.
    var hasActiveWork = false
    /// Whether a verified break-glass release covers this lockout window.
    var isBreakGlassActive = false
}

/// Small state machine that drives the optional auto-shutdown sequence after
/// curfew lockout begins.
///
/// Flow:
/// 1. Lockout starts → move to `.scheduled(date:)` with `date = now + delay`.
/// 2. On later ticks, once `now >= date`, request graceful termination and
///    attempt shutdown.
///    - Success → `.completed`.
///    - Failure → `.retryScheduled(date: now + 60)` and retry once.
/// 3. Retry fails → `.failed`. Lockout remains active (caller is responsible
///    for keeping the screen locked regardless of shutdown outcome).
///
/// If lockout ends, auto-shutdown is disabled, or the workflow already
/// completed, the machine resets to `.idle`. The state is intentionally
/// value-typed and `Equatable` so callers can diff snapshots cheaply and
/// tests can compare expected phases directly.
struct ShutdownWorkflow: Equatable {
    /// Current position in the shutdown sequence.
    enum Phase: Equatable {
        /// Either not in lockout yet, or auto-shutdown disabled.
        case idle
        /// First shutdown attempt queued for the given fire date.
        case scheduled(date: Date)
        /// Second (retry) attempt queued for the given fire date.
        case retryScheduled(date: Date)
        /// Both attempts failed; lockout must stay active by other means.
        case failed
        /// System Events automation was denied by the user.
        case permissionDenied
        /// Shutdown command was dispatched successfully.
        case completed
        /// A protected-work claim is live, so the attempt is on hold until
        /// `until` at the latest. The bound comes from
        /// ``ProtectedWorkPolicy/maximumDeferral``.
        case deferred(until: Date)
        /// A verified break-glass record is standing auto-shutdown down. Not
        /// terminal: the release is re-read every tick, so revoking it re-arms
        /// the workflow the same way it re-arms the daemon.
        case releasedByBreakGlass
    }

    /// Externally read-only view of the workflow's current state. Mutated
    /// only by `update(now:isLocked:isEnabled:delayMinutes:controller:…)`.
    private(set) var phase: Phase = .idle

    /// The shared decision the privileged daemon also consults. Lives here
    /// rather than in the caller so the deferral bound is measured from the
    /// moment the shutdown first came due, not from the most recent tick.
    private var gate = DestructiveActionGate()

    /// Advances the workflow given the current moment and enforcement state.
    ///
    /// - Parameters:
    ///   - now: current clock time; `.scheduled`/`.retryScheduled` fire when
    ///     `now >= phase.date`.
    ///   - isLocked: whether the schedule engine is currently in `.locked`
    ///     phase. Transitions back to `.idle` if lockout ends.
    ///   - isEnabled: user's auto-shutdown setting.
    ///   - delayMinutes: how long to wait after lockout begins before the
    ///     first shutdown attempt. Clamped to a minimum of 1 minute.
    ///   - controller: injection point for graceful-terminate + shutdown.
    ///   - isActiveDevice: whether the user is present at this Mac.
    ///   - protectedWork: allowlist + deferral bound. Passed through to the
    ///     controller so the terminate sweep skips protected apps, and used
    ///     to bound how long a live claim may hold the attempt back.
    ///   - hasActiveProtectedWork: whether any unexpired claim exists.
    ///   - isBreakGlassActive: whether a verified emergency release covers
    ///     this lockout window.
    mutating func update(
        now: Date,
        isLocked: Bool,
        isEnabled: Bool,
        delayMinutes: Int,
        controller: ShutdownControlling,
        isActiveDevice: Bool = true,
        protectedWork: ProtectedWorkPolicy = .default,
        hasActiveProtectedWork: Bool = false,
        isBreakGlassActive: Bool = false
    ) {
        guard isLocked, isEnabled else {
            phase = .idle
            gate = DestructiveActionGate()
            return
        }

        let context = ProtectedWorkContext(
            policy: protectedWork,
            hasActiveWork: hasActiveProtectedWork,
            isBreakGlassActive: isBreakGlassActive
        )

        switch phase {
        case .idle:
            // Active device follows the configured delay so the user has
            // time to save. Idle devices get a shorter default — 2 min —
            // since the user isn't there and the delay's only purpose is
            // a graceful app termination grace period, not user save-time.
            let delay = isActiveDevice ? max(1, delayMinutes) : 2
            phase = .scheduled(date: now.addingTimeInterval(TimeInterval(delay * 60)))
        case .scheduled(let date):
            guard now >= date else {
                return
            }
            phase = attemptOrHold(
                now: now,
                controller: controller,
                context: context,
                failurePhase: .retryScheduled(date: now.addingTimeInterval(60))
            )
        case .retryScheduled(let date):
            guard now >= date else {
                return
            }
            phase = attemptOrHold(
                now: now,
                controller: controller,
                context: context,
                failurePhase: .failed
            )
        case .deferred, .releasedByBreakGlass:
            // Both are holds, not endings. A release that gets revoked must
            // re-arm the app exactly as it re-arms the daemon, so neither may
            // be terminal — re-ask the gate every tick and let it decide.
            phase = attemptOrHold(
                now: now,
                controller: controller,
                context: context,
                failurePhase: .retryScheduled(date: now.addingTimeInterval(60))
            )
        case .failed, .permissionDenied, .completed:
            return
        }
    }

    /// Human-readable one-liner describing the shutdown state, or `nil` when
    /// there is nothing to tell the user (idle / completed cleanly).
    ///
    /// The model publishes this text so the lockout screen can render a
    /// countdown ("Your Mac is going to sleep in 9:45.") without having to
    /// know about workflow internals.
    func statusLine(now: Date) -> String? {
        switch phase {
        case .scheduled(let date):
            let remaining = max(0, Int(date.timeIntervalSince(now)))
            return "Your Mac is going to sleep in \(ShutdownWorkflow.format(seconds: remaining))."
        case .retryScheduled(let date):
            let remaining = max(0, Int(date.timeIntervalSince(now)))
            return "Retrying shutdown in \(ShutdownWorkflow.format(seconds: remaining))."
        case .permissionDenied:
            return """
            Auto shutdown needs permission in System Settings > Privacy & Security > \
            Automation > Curfew > System Events. Lockout remains active.
            """
        case .failed:
            return "Shutdown failed. Lockout remains active."
        case .deferred(let until):
            let remaining = max(0, Int(until.timeIntervalSince(now)))
            return """
            Protected work is running. Shutdown is held for up to \
            \(ShutdownWorkflow.format(seconds: remaining)) more. Lockout remains active.
            """
        case .releasedByBreakGlass:
            return """
            Emergency release in effect. Auto shutdown is standing down; \
            lockout remains active.
            """
        case .completed, .idle:
            return nil
        }
    }

    /// Asks the shared gate whether the attempt may run, and runs it if so.
    ///
    /// Reached only once the scheduled delay has elapsed, which is why `isDue`
    /// is `true` — the app's equivalent of the daemon's stale-heartbeat test
    /// is the `now >= date` guard at the call site.
    private mutating func attemptOrHold(
        now: Date,
        controller: ShutdownControlling,
        context: ProtectedWorkContext,
        failurePhase: Phase
    ) -> Phase {
        switch gate.evaluate(
            now: now,
            isDue: true,
            isBreakGlassActive: context.isBreakGlassActive,
            hasActiveProtectedWork: context.hasActiveWork,
            maximumDeferral: context.policy.maximumDeferral
        ) {
        case .standDown:
            .releasedByBreakGlass
        case .hold(let until):
            .deferred(until: until)
        case .proceed:
            performShutdownAttempt(
                controller: controller,
                protectedWork: context.policy,
                failurePhase: failurePhase
            )
        }
    }

    private func performShutdownAttempt(
        controller: ShutdownControlling,
        protectedWork: ProtectedWorkPolicy,
        failurePhase: Phase
    ) -> Phase {
        controller.requestGracefulTermination(sparing: protectedWork)
        switch controller.executeShutdown() {
        case .succeeded:
            return Phase.completed
        case .permissionDenied:
            return Phase.permissionDenied
        case .failed:
            return failurePhase
        }
    }

    /// Formats seconds as `M:SS` with a zero-padded second component.
    private static func format(seconds: Int) -> String {
        let minutes = seconds / 60
        let secondComponent = seconds % 60
        return String(format: "%d:%02d", minutes, secondComponent)
    }
}
