@testable import Curfew
import SwiftUI
import Testing

/// Shape and type tokens from the spec: three radii, seven spacing steps, and
/// rounded type for numerals, headlines and buttons.
struct HorizonTokensTests {
    @Test("Three radii: 8 for controls, 20 for panels, capsule for floating buttons")
    func radii() {
        #expect(CurfewRadius.control == 8)
        #expect(CurfewRadius.panel == 20)
    }

    @Test("Spacing steps are 4, 8, 12, 16, 24, 40, 64 and nothing else")
    func spacing() {
        #expect(CurfewSpacing.steps == [4, 8, 12, 16, 24, 40, 64])
        let named: [CGFloat] = [
            CurfewSpacing.xSmall, CurfewSpacing.small, CurfewSpacing.medium,
            CurfewSpacing.large, CurfewSpacing.xLarge, CurfewSpacing.xxLarge,
            CurfewSpacing.xxxLarge, CurfewSpacing.section
        ]
        for value in named {
            #expect(CurfewSpacing.steps.contains(value))
        }
    }

    @Test("Numerals, headlines and buttons are rounded; body is the default design")
    func typeRoles() {
        #expect(SundownType.Role.display.design == .rounded)
        #expect(SundownType.Role.figure.design == .rounded)
        #expect(SundownType.Role.headline.design == .rounded)
        #expect(SundownType.Role.title.design == .rounded)
        #expect(SundownType.Role.button.design == .rounded)
        #expect(SundownType.Role.body.design == .default)
        #expect(SundownType.Role.strong.design == .default)
        #expect(SundownType.Role.label.design == .default)
    }

    @Test("Every role scales relative to a system text style")
    func rolesScale() {
        for role in SundownType.Role.allCases {
            #expect(role.relativeTo != nil)
        }
        #expect(SundownType.Role.body.relativeTo == .body)
        #expect(SundownType.Role.display.relativeTo == .largeTitle)
    }
}
