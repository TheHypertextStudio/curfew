import AppKit
import CurfewKit
import Foundation
import OSLog

private let ownershipLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "enforcement-ownership"
)

/// Identity of the Curfew that currently holds the user in lockout, persisted
/// to the flavor-neutral lock file so any flavor can see who owns enforcement.
struct EnforcementOwner: Codable, Equatable {
    /// Raw ``CurfewFlavor`` value of the owning build.
    let flavor: String
    /// Bundle identifier of the owning process. Distinguishes flavors and lets
    /// a liveness check detect a reused pid (different app, same number).
    let bundleIdentifier: String
    /// Human-facing name — `"Curfew"` or `"Curfew (Dev)"` — for UI copy.
    let displayName: String
    /// Process id of the owning app, used for liveness checks.
    let processIdentifier: Int32
    /// When ownership was taken. Informational / for debugging.
    let acquiredAt: Date

    /// Precedence of the owning flavor; an unknown raw value ranks below all
    /// real flavors so a corrupt record can always be reclaimed.
    var enforcementPriority: Int {
        CurfewFlavor(rawValue: flavor)?.enforcementPriority ?? -1
    }
}

/// Cross-flavor mutual exclusion for the *act of locking the user out*.
///
/// Data is isolated per flavor (see ``CurfewFlavor``), but enforcement is
/// deliberately shared: only one Curfew may hold the user in lockout at a time,
/// otherwise two builds could install duelling key taps and stack full-screen
/// overlays. The rendezvous is a single flavor-neutral lock file,
/// ``SharedPaths/enforcementOwnerLock``.
///
/// Precedence is by ``CurfewFlavor/enforcementPriority`` — production always
/// wins, so a stray development build can never block the curfew the user
/// actually relies on, and it steps aside the instant production needs to
/// enforce. A tie (which only arises between two same-flavor processes) goes to
/// the incumbent. Dead or stale owners — pid gone, or pid reused by an
/// unrelated process — are reclaimed.
///
/// The read-modify-write across processes is not atomic, but precedence is
/// deterministic (production always outranks development), so the only possible
/// conflict is two same-flavor processes racing, where a one-tick double-claim
/// resolves on the next reconcile. For a once-per-second reconcile that window
/// is immaterial.
@MainActor
enum EnforcementOwnership {
    /// Result of an ``acquire(flavor:pid:bundleIdentifier:displayName:now:lockURL:isAlive:)``
    /// attempt.
    enum Acquisition: Equatable {
        /// This process now holds (or already held) enforcement.
        case acquired
        /// Another live, equal-or-higher-priority flavor owns enforcement; the
        /// associated owner drives the "standing by" UI.
        case deniedHeldBy(EnforcementOwner)
    }

    /// Takes or retains enforcement ownership for the current flavor, applying
    /// the precedence rules above. All collaborators are injectable so tests can
    /// drive every branch against a temp file without real processes.
    @discardableResult
    static func acquire(
        flavor: CurfewFlavor = .current,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "studio.hypertext.curfew",
        displayName: String = resolvedDisplayName(),
        now: Date = Date(),
        lockURL: URL = SharedPaths.enforcementOwnerLock,
        isAlive: (EnforcementOwner) -> Bool = defaultIsAlive
    ) -> Acquisition {
        let incumbent = readOwner(at: lockURL)
        let mine = EnforcementOwner(
            flavor: flavor.rawValue,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            processIdentifier: pid,
            acquiredAt: now
        )

        if let owner = incumbent, owner.processIdentifier != pid, isAlive(owner) {
            // A different live process owns it. We may take over only if we
            // strictly outrank the incumbent; equal or higher keeps it.
            guard flavor.enforcementPriority > owner.enforcementPriority else {
                return .deniedHeldBy(owner)
            }
            writeOwner(mine, at: lockURL)
            ownershipLogger.info(
                "\(displayName, privacy: .public) preempted enforcement from \(owner.displayName, privacy: .public)"
            )
            return .acquired
        }

        // Free, dead, stale, or already ours → (re)assert ownership. Skip the
        // write when the record already names this process, to avoid rewriting
        // (and bumping the timestamp on) the lock every tick.
        let alreadyOurs = incumbent.map { isOwnedByUs(
            $0,
            pid: pid,
            bundleIdentifier: bundleIdentifier
        ) } ?? false
        if !alreadyOurs {
            writeOwner(mine, at: lockURL)
        }
        return .acquired
    }

    /// Releases ownership, but only when this process is the recorded owner —
    /// so a non-owning flavor calling this never deletes someone else's lock.
    static func release(
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "studio.hypertext.curfew",
        lockURL: URL = SharedPaths.enforcementOwnerLock,
        fileManager: FileManager = .default
    ) {
        guard let owner = readOwner(at: lockURL),
              isOwnedByUs(owner, pid: pid, bundleIdentifier: bundleIdentifier)
        else {
            return
        }
        try? fileManager.removeItem(at: lockURL)
        ownershipLogger.info("released enforcement ownership")
    }

    /// The current live owner, or `nil` when enforcement is free (no record, or
    /// the recorded owner is gone). Use to drive read-only UI.
    static func currentOwner(
        lockURL: URL = SharedPaths.enforcementOwnerLock,
        isAlive: (EnforcementOwner) -> Bool = defaultIsAlive
    ) -> EnforcementOwner? {
        guard let owner = readOwner(at: lockURL), isAlive(owner) else { return nil }
        return owner
    }

    // MARK: - Liveness

    /// Default liveness probe: the pid must map to a running application whose
    /// bundle identifier matches the record. The bundle-id match guards against
    /// a pid the OS has since handed to an unrelated process.
    ///
    /// `nonisolated` so it can serve as the `isAlive` default argument (default
    /// expressions are evaluated outside the enum's main-actor isolation);
    /// `NSRunningApplication` is thread-safe.
    nonisolated static func defaultIsAlive(_ owner: EnforcementOwner) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: owner.processIdentifier) else {
            return false
        }
        return app.bundleIdentifier == owner.bundleIdentifier
    }

    // MARK: - Private

    /// Returns `true` when `owner` was written by this process — same pid AND
    /// bundle identifier. Used by both `acquire` and `release` so the two-field
    /// ownership predicate lives in one place.
    private static func isOwnedByUs(
        _ owner: EnforcementOwner,
        pid: Int32,
        bundleIdentifier: String
    ) -> Bool {
        owner.processIdentifier == pid && owner.bundleIdentifier == bundleIdentifier
    }

    /// `nonisolated` so it can serve as the `displayName` default argument;
    /// `Bundle.main` and ``CurfewFlavor/current`` are both safe off the main
    /// actor.
    private nonisolated static func resolvedDisplayName() -> String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !name.isEmpty {
            return name
        }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return "Curfew\(CurfewFlavor.current.displaySuffix)"
    }

    private static func readOwner(at lockURL: URL) -> EnforcementOwner? {
        guard let data = try? Data(contentsOf: lockURL) else { return nil }
        return try? JSONDecoder().decode(EnforcementOwner.self, from: data)
    }

    private static func writeOwner(_ owner: EnforcementOwner, at lockURL: URL) {
        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(owner)
            try data.write(to: lockURL, options: .atomic)
        } catch {
            ownershipLogger.error(
                "failed to write enforcement owner: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
