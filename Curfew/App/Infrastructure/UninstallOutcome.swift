import Foundation

extension UninstallCoordinator {
    static func registrationPreflight(
        flavor: CurfewFlavor,
        unregisterServices: (() -> [String])?
    ) -> Outcome? {
        guard flavor == .studioDevelopment else { return nil }
        guard let unregisterServices else {
            return Outcome(
                removed: [],
                failed: [("Background services", "Registration cleanup was unavailable.")],
                blockedBeforeCleanup: true
            )
        }
        let failures = unregisterServices()
        guard !failures.isEmpty else { return nil }
        return Outcome(
            removed: [],
            failed: failures.map { ("Background services", $0) },
            blockedBeforeCleanup: true
        )
    }

    /// Result of a full uninstall run.
    struct Outcome: Equatable {
        /// Paths that were successfully removed.
        let removed: [String]

        /// Paths that failed to remove, paired with the best-effort reason.
        let failed: [(path: String, reason: String)]

        /// A registered service could not be removed, so no saved state was erased.
        let blockedBeforeCleanup: Bool

        init(
            removed: [String],
            failed: [(path: String, reason: String)],
            blockedBeforeCleanup: Bool = false
        ) {
            self.removed = removed
            self.failed = failed
            self.blockedBeforeCleanup = blockedBeforeCleanup
        }

        /// `true` when every targeted path was removed.
        var allSucceeded: Bool {
            failed.isEmpty
        }

        /// Summary exposes only path names and registration errors, not file contents.
        var summary: String {
            var lines: [String] = []
            if !removed.isEmpty {
                lines.append("Removed:")
                lines.append(contentsOf: removed.map { "  • \($0)" })
            }
            if !failed.isEmpty {
                lines.append("")
                lines.append("Could not remove:")
                lines.append(contentsOf: failed.map { "  • \($0.path) — \($0.reason)" })
            }
            return lines.joined(separator: "\n")
        }

        /// System-provided error text can vary without changing the result.
        static func == (lhs: Outcome, rhs: Outcome) -> Bool {
            lhs.removed == rhs.removed
                && lhs.failed.map(\.path) == rhs.failed.map(\.path)
                && lhs.blockedBeforeCleanup == rhs.blockedBeforeCleanup
        }
    }
}

/// Prevents the live model from recreating state only after cleanup completed.
@MainActor
enum UninstallLifecycle {
    static func finish(
        outcome: UninstallCoordinator.Outcome,
        present: (UninstallCoordinator.Outcome) -> Void,
        terminate: () -> Void
    ) {
        present(outcome)
        if !outcome.blockedBeforeCleanup {
            terminate()
        }
    }
}
