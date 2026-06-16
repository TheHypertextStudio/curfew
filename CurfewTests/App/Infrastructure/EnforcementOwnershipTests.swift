@testable import Curfew
import Foundation
import Testing

/// Unit tests for the cross-flavor single-enforcer lock. Every collaborator is
/// injected so the tests run against a throwaway temp file and never touch the
/// real lock or probe the machine's running apps.
@MainActor
struct EnforcementOwnershipTests {
    private func tempLock() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-enforce-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("enforcement-owner.json")
    }

    private let alive: (EnforcementOwner) -> Bool = { _ in true }
    private let dead: (EnforcementOwner) -> Bool = { _ in false }
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Acquires the lock as `flavor`, deriving the bundle id and display name
    /// the way the running build would, so call sites stay terse.
    @discardableResult
    private func seed(
        _ flavor: CurfewFlavor,
        pid: Int32,
        at url: URL,
        isAlive: @escaping (EnforcementOwner) -> Bool
    ) -> EnforcementOwnership.Acquisition {
        EnforcementOwnership.acquire(
            flavor: flavor,
            pid: pid,
            bundleIdentifier: "studio.hypertext.curfew\(flavor.identifierSuffix)",
            displayName: "Curfew\(flavor.displaySuffix)",
            now: now,
            lockURL: url,
            isAlive: isAlive
        )
    }

    @Test("Acquiring a free lock takes ownership")
    func acquiresFreeLock() {
        let url = tempLock()
        let result = seed(.production, pid: 42, at: url, isAlive: alive)
        #expect(result == .acquired)
        let owner = EnforcementOwnership.currentOwner(lockURL: url, isAlive: alive)
        #expect(owner?.processIdentifier == 42)
        #expect(owner?.flavor == "production")
    }

    @Test("A development build stands aside for a live production owner")
    func developmentDeniedByProduction() {
        let url = tempLock()
        seed(.production, pid: 100, at: url, isAlive: alive)
        let result = seed(.development, pid: 200, at: url, isAlive: alive)
        guard case .deniedHeldBy(let owner) = result else {
            Issue.record("expected denial, got \(result)")
            return
        }
        #expect(owner.processIdentifier == 100)
        #expect(owner.displayName == "Curfew")
    }

    @Test("Production preempts a live development owner")
    func productionPreemptsDevelopment() {
        let url = tempLock()
        seed(.development, pid: 200, at: url, isAlive: alive)
        let result = seed(.production, pid: 100, at: url, isAlive: alive)
        #expect(result == .acquired)
        #expect(
            EnforcementOwnership.currentOwner(lockURL: url, isAlive: alive)?
                .processIdentifier == 100
        )
    }

    @Test("A stale (dead) owner is reclaimed even by a lower-priority flavor")
    func reclaimsStaleOwner() {
        let url = tempLock()
        seed(.production, pid: 100, at: url, isAlive: alive)
        // The incumbent outranks the caller, but it's dead — so dev reclaims.
        let result = seed(.development, pid: 200, at: url, isAlive: dead)
        #expect(result == .acquired)
        #expect(
            EnforcementOwnership.currentOwner(lockURL: url, isAlive: alive)?
                .processIdentifier == 200
        )
    }

    @Test("Release frees the lock only for the owning process")
    func releaseRespectsOwnership() {
        let url = tempLock()
        seed(.production, pid: 100, at: url, isAlive: alive)
        // A non-owning pid cannot release it.
        EnforcementOwnership.release(pid: 999, lockURL: url)
        #expect(
            EnforcementOwnership.currentOwner(lockURL: url, isAlive: alive)?
                .processIdentifier == 100
        )
        // The owner can.
        EnforcementOwnership.release(pid: 100, lockURL: url)
        #expect(EnforcementOwnership.currentOwner(lockURL: url, isAlive: alive) == nil)
    }

    @Test("currentOwner reports nil when the recorded owner is gone")
    func currentOwnerNilWhenDead() {
        let url = tempLock()
        seed(.production, pid: 100, at: url, isAlive: alive)
        #expect(EnforcementOwnership.currentOwner(lockURL: url, isAlive: dead) == nil)
    }
}
