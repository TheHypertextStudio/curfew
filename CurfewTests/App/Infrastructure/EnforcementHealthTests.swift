@testable import Curfew
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
            tapIsActive: false
        )

        #expect(health == .active)
        #expect(health.isFullyActive)
        #expect(health.bannerTitle == nil)
        #expect(health.menuBarBadgeSymbol == nil)
    }

    @Test("Degraded banner copy states enforcement is not active and how to fix it")
    func degradedCopyExplainsRemediation() {
        let noAccessibility = EnforcementHealth.degradedNoAccessibility
        #expect(noAccessibility.bannerTitle?.contains("not active") == true)
        #expect(noAccessibility.bannerDetail?.contains("Accessibility") == true)

        let tapDown = EnforcementHealth.degradedTapDown
        #expect(tapDown.bannerTitle?.contains("not active") == true)
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
        #expect(noAccessibility?.contains("not active") == true)

        let tapDown = EnforcementHealth.degradedTapDown.compactPopoverMessage
        #expect(tapDown?.isEmpty == false)
    }

    @Test("Settings status title is defined for every case and reads plainly")
    func settingsStatusTitleDefinedForEveryCase() {
        #expect(EnforcementHealth.active.settingsStatusTitle == "Enforcement is active")
        #expect(
            EnforcementHealth.degradedNoAccessibility.settingsStatusTitle
                .contains("not active")
        )
        #expect(EnforcementHealth.degradedTapDown.settingsStatusTitle.contains("not active"))
    }

    @Test("Only degraded states offer the fix-it affordance")
    func fixItAffordanceOnlyWhenDegraded() {
        #expect(EnforcementHealth.active.offersAccessibilityRemediation == false)
        #expect(EnforcementHealth.degradedNoAccessibility.offersAccessibilityRemediation)
        #expect(EnforcementHealth.degradedTapDown.offersAccessibilityRemediation)
    }
}
