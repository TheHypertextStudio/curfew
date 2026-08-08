import ArgumentParser
import CurfewKit
import Foundation

/// Emergency release for root-level enforcement, reachable from any terminal.
///
/// The privileged daemon answers a missing Curfew app during lockout with
/// `/sbin/shutdown -h +1`, which user space cannot cancel. That turns every
/// ordinary recovery move — killing a wedged app, rebooting a crash loop,
/// debugging enforcement — into a forced power-off, with the only offered
/// remedy sitting behind a locked display. An escape that depends on the thing
/// that is broken is not an escape.
///
/// So this command exists, and it works over SSH, from a second Mac, or from a
/// terminal the lockout overlay is covering. It writes a signed release the
/// daemon honors for the rest of the current lockout window, and — when run as
/// root — kills a shutdown that is already counting down.
///
/// It does not unlock the display and it does not shorten the curfew. Standing
/// enforcement's *consequences* down is not the same as ending enforcement.
struct BreakGlassCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "break-glass",
        abstract: "Emergency release: stand root-level enforcement down for this lockout.",
        discussion: """
        Writes a signed release record that the Curfew app and the privileged \
        daemon both honor until the current lockout window ends. Run it under \
        sudo to also cancel a /sbin/shutdown the daemon has already issued — \
        that countdown cannot be stopped from user space.

        The display stays locked and the curfew still ends when it was always \
        going to end. Every release is recorded with its reason.
        """
    )

    @Option(
        name: .shortAndLong,
        help: "Why you are releasing. At least \(BreakGlassStore.minimumReasonCharacters) characters."
    )
    var reason: String

    @Flag(name: .long, help: "Print what would happen without writing anything.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Remove an existing release instead of issuing one.")
    var revoke: Bool = false

    func run() throws {
        let store = BreakGlassStore()

        if revoke {
            store.clear()
            print("break-glass: release revoked. Enforcement resumes on the next daemon tick.")
            return
        }

        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= BreakGlassStore.minimumReasonCharacters else {
            throw ValidationError(
                "Reason must be at least \(BreakGlassStore.minimumReasonCharacters) characters; got \(trimmed.count)."
            )
        }

        if dryRun {
            print("break-glass: would write \(store.recordURL.path)")
            print("break-glass: reason — \(trimmed)")
            print(
                "break-glass: would \(geteuid() == 0 ? "cancel" : "NOT cancel") a pending /sbin/shutdown (running as \(geteuid() == 0 ? "root" : "a normal user"))"
            )
            return
        }

        let release = try store.issue(
            reason: trimmed,
            issuedBy: Self.issuerIdentity(),
            now: Date()
        )
        print("break-glass: release \(release.id.uuidString) written to \(store.recordURL.path)")

        // Only root can signal the shutdown process. Say so plainly rather
        // than failing quietly — a user who runs this without sudo during an
        // active countdown needs to know the countdown is still running.
        if geteuid() == 0 {
            let cancelled = SystemShutdownCanceller().cancelPendingShutdown()
            print(
                cancelled
                    ? "break-glass: cancelled a pending /sbin/shutdown."
                    : "break-glass: no pending /sbin/shutdown to cancel."
            )
        } else {
            print(
                "break-glass: not running as root, so a /sbin/shutdown already in flight was NOT cancelled."
            )
            print("break-glass: re-run as `sudo curfew-ctl break-glass --reason \"…\"` to stop it.")
        }

        print(
            "break-glass: the display stays locked and the curfew still ends at its scheduled time."
        )
    }

    /// `user@host`, recorded on the release for the audit trail.
    static func issuerIdentity() -> String {
        let user = ProcessInfo.processInfo.environment["SUDO_USER"]
            ?? NSUserName()
        let host = ProcessInfo.processInfo.hostName
        return "\(user)@\(host)"
    }
}
