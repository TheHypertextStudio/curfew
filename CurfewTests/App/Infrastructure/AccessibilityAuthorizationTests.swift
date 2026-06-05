@testable import Curfew
import Testing

struct AccessibilityAuthorizationTests {
    @Test("Fake reports its scripted trust value and counts the call")
    func fakeHonorsScriptedTrust() {
        let trustedFake = FakeAccessibilityAuthorization(trusted: true)
        #expect(trustedFake.isTrusted())
        #expect(trustedFake.isTrustedCallCount == 1)

        let untrustedFake = FakeAccessibilityAuthorization(trusted: false)
        #expect(untrustedFake.isTrusted() == false)
        #expect(untrustedFake.isTrustedCallCount == 1)
    }

    @Test("Fake reports its scripted prompt result and counts the call")
    func fakeHonorsScriptedPromptResult() {
        let fake = FakeAccessibilityAuthorization(trusted: false, promptResult: true)
        #expect(fake.promptForTrust())
        #expect(fake.promptForTrustCallCount == 1)
    }

    @Test("Enforcement health composes with the trust seam to flip on trust")
    func resolveComposesWithTrustSeam() {
        let trustedFake = FakeAccessibilityAuthorization(trusted: true)
        let trustedHealth = EnforcementHealth.resolve(
            isAccessibilityTrusted: trustedFake.isTrusted(),
            tapExpectedActive: true,
            tapIsActive: true
        )
        #expect(trustedHealth == .active)

        let untrustedFake = FakeAccessibilityAuthorization(trusted: false)
        let untrustedHealth = EnforcementHealth.resolve(
            isAccessibilityTrusted: untrustedFake.isTrusted(),
            tapExpectedActive: true,
            tapIsActive: true
        )
        #expect(untrustedHealth == .degradedNoAccessibility)
    }
}
