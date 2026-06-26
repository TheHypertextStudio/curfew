@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Unit tests for the pure watchdog decision that drives
/// ``LockoutKeyInterceptor``'s self-healing loop.
///
/// The live event tap, OS re-enable, and timer firing cannot run headlessly,
/// so they are exercised only through manual QA on a signed build. What *is*
/// unit-testable — and what these tests pin down — is the pure mapping from the
/// tap's observable facts (installed? OS-enabled?) to the remediation the
/// watchdog should take.
struct TapWatchdogDecisionTests {
    @Test("An installed, OS-enabled tap is healthy and needs no action")
    func installedAndEnabledIsHealthy() {
        #expect(
            LockoutKeyInterceptor.TapWatchdogDecision.decide(
                installed: true,
                enabled: true
            ) == .healthy
        )
    }

    @Test("An installed but OS-disabled tap is re-enabled in place")
    func installedButDisabledReEnables() {
        #expect(
            LockoutKeyInterceptor.TapWatchdogDecision.decide(
                installed: true,
                enabled: false
            ) == .reEnable
        )
    }

    @Test("A vanished (uninstalled) tap is recreated from scratch")
    func uninstalledRecreates() {
        #expect(
            LockoutKeyInterceptor.TapWatchdogDecision.decide(
                installed: false,
                enabled: false
            ) == .recreate
        )
    }

    @Test("Recreation wins even if a stale enabled flag lingers on a vanished tap")
    func uninstalledRecreatesRegardlessOfEnabledFlag() {
        #expect(
            LockoutKeyInterceptor.TapWatchdogDecision.decide(
                installed: false,
                enabled: true
            ) == .recreate
        )
    }
}
