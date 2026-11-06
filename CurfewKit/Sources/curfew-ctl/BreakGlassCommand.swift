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
        abstract: "Emergency release: suspend app termination and shutdown for this lockout.",
        discussion: """
        Writes a signed release record that the Curfew app and the privileged \
        daemon both honor until the current lockout window ends. Run it under \
        sudo to also cancel a /sbin/shutdown the daemon has already issued — \
        that countdown cannot be stopped from user space.

        The display stays locked and the scheduled unlock time stays unchanged. \
        Curfew records every release with its reason.
        """
    )

    @Option(
        name: .shortAndLong,
        help: "Why you need an emergency release. At least \(BreakGlassStore.minimumReasonCharacters) characters."
    )
    var reason: String?

    @Flag(
        name: [.long, .customShort("n")],
        help: "Print what would happen without writing anything."
    )
    var dryRun: Bool = false

    @Flag(name: .long, help: "Remove an existing release instead of issuing one.")
    var revoke: Bool = false

    @OptionGroup var options: CLIOptions

    func run() throws {
        if !revoke {
            _ = try validatedReason()
        }
        let isRoot = geteuid() == 0
        let store: BreakGlassStore
        let storage: BreakGlassUserStorage
        if isRoot {
            let user = try BreakGlassRecoveryUser.consoleUser()
            if !dryRun {
                try BreakGlassOwnershipRepair.repair(user: user, flavor: .current)
            }
            store = user.store()
            storage = BreakGlassUserStorage(user: user, credentials: SystemBreakGlassCredentials())
        } else {
            store = BreakGlassStore()
            storage = .currentUser
        }
        let result = try output(
            store: store,
            canceller: SystemShutdownCanceller(),
            isRoot: isRoot,
            now: Date(),
            issuedBy: Self.issuerIdentity(),
            storageAccess: storage
        )
        if options.json {
            try CLIOutput.printJSON(["message": result, "dry_run": dryRun, "revoked": revoke])
        } else {
            try CLIText.print(result, title: "Emergency recovery", options: options)
        }
    }

    func output(
        store: BreakGlassStore,
        canceller: any PendingShutdownCanceling,
        isRoot: Bool,
        now: Date,
        issuedBy: String,
        storageAccess: BreakGlassUserStorage = .currentUser
    ) throws -> String {
        var lines: [String] = []

        if dryRun, revoke {
            return "break-glass: would remove \(store.recordURL.path). Enforcement would resume on the next daemon tick."
        }

        if revoke {
            try storageAccess.perform { try store.revoke() }
            return "break-glass: release revoked. Enforcement resumes on the next daemon tick."
        }

        let trimmed = try validatedReason()

        if dryRun {
            lines.append("break-glass: would write \(store.recordURL.path)")
            lines.append("break-glass: reason — \(trimmed)")
            lines.append(
                "break-glass: would \(isRoot ? "cancel" : "NOT cancel") a pending /sbin/shutdown (running as \(isRoot ? "root" : "a normal user"))"
            )
            return lines.joined(separator: "\n")
        }

        let release = try storageAccess.perform {
            try store.issue(reason: trimmed, issuedBy: issuedBy, now: now)
        }
        lines
            .append(
                "break-glass: release \(release.id.uuidString) written to \(store.recordURL.path)"
            )

        do {
            lines += try shutdownCancellationLines(canceller: canceller, isRoot: isRoot)
        } catch {
            throw EmergencyShutdownCancellationFailure(message:
                "Emergency release \(release.id.uuidString) was saved to \(store.recordURL.path). " +
                    "Shutdown cancellation failed: \(error.localizedDescription) " +
                    "A pending shutdown may still be running."
            )
        }

        lines.append(
            "break-glass: the display stays locked and the curfew still ends at its scheduled time."
        )
        return lines.joined(separator: "\n")
    }

    private func validatedReason() throws -> String {
        let trimmed = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= BreakGlassStore.minimumReasonCharacters else {
            throw ValidationError(
                "Reason must be at least \(BreakGlassStore.minimumReasonCharacters) characters; got \(trimmed.count)."
            )
        }
        return trimmed
    }

    private func shutdownCancellationLines(
        canceller: any PendingShutdownCanceling,
        isRoot: Bool
    ) throws -> [String] {
        // Only root can signal shutdown. A user needs to know that their
        // release cannot stop a countdown the daemon already started.
        guard isRoot else {
            return [
                "break-glass: not running as root, so a pending /sbin/shutdown was NOT cancelled.",
                "break-glass: run `sudo curfew-ctl break-glass --reason \"…\"` to stop it."
            ]
        }
        return try [canceller.cancelPendingShutdown()
            ? "break-glass: cancelled a pending /sbin/shutdown."
            : "break-glass: no pending /sbin/shutdown to cancel."]
    }

    /// `user@host`, recorded on the release for the audit trail.
    static func issuerIdentity() -> String {
        let user = ProcessInfo.processInfo.environment["SUDO_USER"]
            ?? NSUserName()
        let host = ProcessInfo.processInfo.hostName
        return "\(user)@\(host)"
    }
}

private struct EmergencyShutdownCancellationFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
