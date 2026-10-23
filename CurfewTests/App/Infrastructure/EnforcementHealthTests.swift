@testable import Curfew
@testable import CurfewKit
import Testing

struct EnforcementHealthTests {
    @Test("Missing Accessibility trust degrades regardless of tap state")
    func untrustedAlwaysDegradesNoAccessibility() {
        for tapExpectedActive in [true, false] {
            for tapIsActive in [true, false] {
                let health = EnforcementHealth.resolve(
                    isAccessibilityTrusted: false,
                    tapExpectedActive: tapExpectedActive,
                    tapIsActive: tapIsActive
                )

                #expect(health == .degradedNoAccessibility)
                #expect(health.isFullyActive == false)
                #expect(health.bannerTitle != nil)
                #expect(health.bannerDetail != nil)
                #expect(health.menuBarBadgeSymbol != nil)
            }
        }
    }

    @Test("Trusted but a downed expected tap reports the keyboard shield is interrupted")
    func trustedWithDownedTapDegradesTapDown() {
        let health = EnforcementHealth.resolve(
            isAccessibilityTrusted: true,
            tapExpectedActive: true,
            tapIsActive: false
        )

        #expect(health == .degradedTapDown)
        #expect(health.isFullyActive == false)
        #expect(health.bannerTitle != nil)
        #expect(health.bannerDetail != nil)
        #expect(health.menuBarBadgeSymbol != nil)
    }

    @Test("Trusted with a live expected tap is fully active and surfaces no banner")
    func trustedWithLiveTapIsActive() {
        let health = EnforcementHealth.resolve(
            isAccessibilityTrusted: true,
            tapExpectedActive: true,
            tapIsActive: true
        )

        #expect(health == .active)
        #expect(health.isFullyActive)
        #expect(health.bannerTitle == nil)
        #expect(health.bannerDetail == nil)
        #expect(health.menuBarBadgeSymbol == nil)
    }

    @Test("An idle tap that is not expected to be running is still healthy")
    func trustedWithIdleUnexpectedTapIsActive() {
        let health = EnforcementHealth.resolve(
            isAccessibilityTrusted: true,
            tapExpectedActive: false,
            tapIsActive: false,
            helperAvailability: .ready
        )

        #expect(health == .active)
        #expect(health.isFullyActive)
        #expect(health.bannerTitle == nil)
        #expect(health.menuBarBadgeSymbol == nil)
    }

    @Test("Privileged helper failures degrade enforcement health")
    func helperFailuresDegradeEnforcementHealth() {
        let expected: [(PrivilegedEnforcementAvailability, EnforcementHealth)] = [
            (.unavailable, .degradedHelperUnavailable),
            (.unauthorized, .degradedHelperUnauthorized),
            (.stale, .degradedHelperStale),
            (.registrationFailed, .degradedHelperRegistration)
        ]

        for (availability, expectedHealth) in expected {
            let health = EnforcementHealth.resolve(
                isAccessibilityTrusted: true,
                tapExpectedActive: false,
                tapIsActive: false,
                helperAvailability: availability
            )

            #expect(health == expectedHealth)
            #expect(health.isFullyActive == false)
            #expect(health.bannerDetail?.contains("Background protection") == true)
            #expect(health.offersAccessibilityRemediation == false)
        }
    }

    @Test("A disabled helper feature does not degrade enforcement health")
    func helperNotRequiredIsHealthy() {
        let health = EnforcementHealth.resolve(
            isAccessibilityTrusted: true,
            tapExpectedActive: false,
            tapIsActive: false,
            helperAvailability: .notRequired
        )

        #expect(health == .active)
    }

    @Test("Degraded banner copy names the missing capability and how to fix it")
    func degradedCopyExplainsRemediation() {
        let noAccessibility = EnforcementHealth.degradedNoAccessibility
        #expect(noAccessibility.bannerTitle == "Keyboard shortcut blocking is unavailable")
        #expect(noAccessibility.bannerDetail?.contains("Accessibility") == true)

        let tapDown = EnforcementHealth.degradedTapDown
        #expect(tapDown.bannerTitle == "Keyboard shortcut blocking was interrupted")
        #expect(tapDown.bannerDetail?.isEmpty == false)
    }

    @Test("Degraded cases share the warning-triangle badge symbol")
    func degradedBadgeUsesWarningTriangle() {
        #expect(
            EnforcementHealth.degradedNoAccessibility.menuBarBadgeSymbol
                == "exclamationmark.triangle.fill"
        )
        #expect(
            EnforcementHealth.degradedTapDown.menuBarBadgeSymbol
                == "exclamationmark.triangle.fill"
        )
    }

    @Test("Compact popover message is nil when active and warns when degraded")
    func compactPopoverMessageTracksHealth() {
        #expect(EnforcementHealth.active.compactPopoverMessage == nil)

        let noAccessibility = EnforcementHealth.degradedNoAccessibility.compactPopoverMessage
        #expect(noAccessibility?.contains("block shortcuts") == true)

        let tapDown = EnforcementHealth.degradedTapDown.compactPopoverMessage
        #expect(tapDown?.isEmpty == false)
    }

    @Test("Settings status title is defined for every case and reads plainly")
    func settingsStatusTitleDefinedForEveryCase() {
        #expect(EnforcementHealth.active
            .settingsStatusTitle == "Keyboard shortcut blocking is available")
        #expect(
            EnforcementHealth.degradedNoAccessibility.settingsStatusTitle
                .contains("Keyboard shortcut blocking is unavailable")
        )
        #expect(EnforcementHealth.degradedTapDown
            .settingsStatusTitle == "Keyboard shortcut blocking was interrupted")
    }

    @Test("Only degraded states offer the fix-it affordance")
    func fixItAffordanceOnlyWhenDegraded() {
        #expect(EnforcementHealth.active.offersAccessibilityRemediation == false)
        #expect(EnforcementHealth.degradedNoAccessibility.offersAccessibilityRemediation)
        #expect(EnforcementHealth.degradedTapDown.offersAccessibilityRemediation)
    }
}
