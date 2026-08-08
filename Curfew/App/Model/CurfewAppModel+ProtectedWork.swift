import Foundation
import OSLog

private let protectedWorkLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "protected-work"
)

/// The app's half of the protected-work carve-out: reading live claims,
/// honoring a break-glass release, and publishing the policy where the root
/// daemon can see it.
///
/// Design notes and the break-glass runbook live in
/// `Documentation/protected-work.md`.
@MainActor
extension CurfewAppModel {
    /// The carve-out's three inputs, read fresh every tick.
    ///
    /// This is the glue the shutdown workflow runs on, so it is a named
    /// function rather than three arguments inlined at the call site: a
    /// wiring test can assert that the user's policy, the live claims file,
    /// and the emergency release all actually arrive.
    func protectedWorkContext() -> ProtectedWorkContext {
        ProtectedWorkContext(
            policy: settings.protectedWork,
            hasActiveWork: protectedWork.claims.hasActiveWork(now: currentTime),
            isBreakGlassActive: isBreakGlassActive()
        )
    }

    /// Whether a verified emergency release covers the lockout window in
    /// progress.
    ///
    /// Scoped to the current window by handing the store the durable record's
    /// `lockoutStartedAt`: a release issued during last night's incident must
    /// not stand tonight's enforcement down.
    func isBreakGlassActive() -> Bool {
        protectedWork.breakGlass.activeRelease(
            now: currentTime,
            issuedAfter: lockoutDeadlineStore.load()?.lockoutStartedAt
        ) != nil
    }

    /// Publishes the protected-work policy where the privileged daemon can
    /// read it. The daemon runs as root and cannot see the user's
    /// `UserDefaults` domain, so without this mirror it would fall back to
    /// ``ProtectedWorkPolicy/default`` and quietly ignore the user's edits.
    func mirrorProtectedWorkPolicy() {
        guard !RuntimeEnvironment.isUnitTestHost else { return }
        do {
            try settings.protectedWork.writeMirror()
        } catch {
            protectedWorkLogger.error(
                "failed to mirror protected-work policy: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
