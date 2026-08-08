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
    }
}
