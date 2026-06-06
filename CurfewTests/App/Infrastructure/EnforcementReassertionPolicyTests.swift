@testable import Curfew
import Testing

/// Unit tests for the pure ``EnforcementReassertionPolicy`` that decides whether
/// returning to the Mac (app activation / system wake) should re-assert the
/// lockout shield and overlay.
struct EnforcementReassertionPolicyTests {
    @Test("Locked with a downed tap re-asserts enforcement")
    func lockedTapDownReasserts() {
        #expect(
            EnforcementReassertionPolicy.decide(
                phase: .locked,
                tapIsActive: false
            ) == .reassert
        )
    }

    @Test("Locked with a live tap still re-asserts to restore overlay z-order")
    func lockedTapUpReasserts() {
        #expect(
            EnforcementReassertionPolicy.decide(
                phase: .locked,
                tapIsActive: true
            ) == .reassert
        )
    }

    @Test("Non-locked phases never re-assert, regardless of tap state")
    func nonLockedIsNoop() {
        for phase in [EnforcementPhase.working, .warning, .dayOff] {
            for tapIsActive in [true, false] {
                #expect(
                    EnforcementReassertionPolicy.decide(
                        phase: phase,
                        tapIsActive: tapIsActive
                    ) == .noop
                )
            }
        }
    }
}
