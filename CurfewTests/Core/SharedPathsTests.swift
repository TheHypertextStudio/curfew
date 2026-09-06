@testable import Curfew
import Foundation
import Testing

/// Behaviour tests for ``SharedPaths`` home resolution.
///
/// This exists because of a bug the protected-work work uncovered: the
/// privileged daemon runs as root, where `NSHomeDirectory()` answers
/// `/var/root`, so every shared path it derived pointed at a directory the app
/// never writes. It saw no lockout deadline, no heartbeat, and — once the
/// carve-out landed — would have seen no protected work either, which is the
/// worst possible reading to be wrong about.
struct SharedPathsTests {
    @Test("A normal user always gets their own process home back")
    func nonRootIsUnchanged() {
        let resolved = SharedPaths.resolveHomeDirectory(
            processHome: "/Users/willie",
            effectiveUserID: 501,
            consoleUserHome: "/Users/someone-else"
        )
        #expect(resolved == "/Users/willie")
    }

    @Test("Root resolves the console user's home instead of /var/root")
    func rootRedirectsToTheConsoleUser() {
        let resolved = SharedPaths.resolveHomeDirectory(
            processHome: "/var/root",
            effectiveUserID: 0,
            consoleUserHome: "/Users/willie"
        )
        #expect(resolved == "/Users/willie")
    }

    @Test("Root with nobody logged in falls back rather than guessing")
    func rootWithoutConsoleUserFallsBack() {
        #expect(
            SharedPaths.resolveHomeDirectory(
                processHome: "/var/root",
                effectiveUserID: 0,
                consoleUserHome: nil
            ) == "/var/root"
        )
        #expect(
            SharedPaths.resolveHomeDirectory(
                processHome: "/var/root",
                effectiveUserID: 0,
                consoleUserHome: ""
            ) == "/var/root"
        )
    }

    @Test("Protected-work and break-glass paths sit beside the MCP queue")
    func newPathsLiveWithTheOtherSharedState() {
        let directory = SharedPaths.applicationSupport
        for url in [
            SharedPaths.protectedWorkClaims,
            SharedPaths.protectedWorkPolicySnapshot,
            SharedPaths.breakGlassRelease,
            SharedPaths.breakGlassSecret
        ] {
            #expect(url.deletingLastPathComponent() == directory)
        }
        // The deferral marker is the one piece of this state root owns, so it
        // must not live anywhere the user can rewrite it.
        #expect(
            SharedPaths.enforcementDeferralMarker.path
                .hasPrefix("/Library/Application Support/Curfew")
        )
        #expect(
            SharedPaths.remoteCommandState.path
                .hasPrefix("/Library/Application Support/Curfew")
        )
        #expect(
            SharedPaths.remoteCommandResults.path
                .hasPrefix("/Library/Application Support/Curfew")
        )
        #expect(
            SharedPaths.remoteCommandResultAcknowledgements.path
                .hasPrefix("/Library/Application Support/Curfew")
        )
    }

    @Test("Privileged state keeps production stable and development isolated")
    func privilegedStateIsFlavorSpecific() {
        #expect(
            SharedPaths.privilegedApplicationSupport(for: .production).path
                == "/Library/Application Support/Curfew"
        )
        #expect(
            SharedPaths.privilegedApplicationSupport(for: .development).path
                == "/Library/Application Support/Curfew (Dev)"
        )
    }
}

struct LockoutDeadlineStoreTests {
    @Test("A durable deadline is replaced atomically and remains private")
    func saveReplacesTheRecordWithPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-deadline-store-\(UUID().uuidString)")
        let recordURL = directory.appendingPathComponent("lockout-deadline.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LockoutDeadlineStore(recordURL: recordURL)
        let first = LockoutDeadlineRecord(
            lockoutStartedAt: Date(timeIntervalSince1970: 100),
            scheduledUnlockAt: Date(timeIntervalSince1970: 200),
            kind: .scheduledTime
        )
        let replacement = LockoutDeadlineRecord(
            lockoutStartedAt: Date(timeIntervalSince1970: 300),
            scheduledUnlockAt: Date(timeIntervalSince1970: 400),
            kind: .remoteCommand
        )

        store.save(first)
        store.save(replacement)

        #expect(store.load() == replacement)
        let attributes = try FileManager.default.attributesOfItem(atPath: recordURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
        let siblings = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(siblings.count == 1)
        #expect(siblings.first?.lastPathComponent == recordURL.lastPathComponent)
    }
}
