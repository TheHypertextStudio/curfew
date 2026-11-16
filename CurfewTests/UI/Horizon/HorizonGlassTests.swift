@testable import Curfew
import SwiftUI
import Testing

/// Glass is the system's Liquid Glass. Reduce Transparency swaps it for a solid
/// panel and Increase Contrast adds an outline.
struct HorizonGlassTests {
    @Test("Standard settings use system glass without an outline")
    func standard() {
        let look = HorizonGlassLook.resolve(reduceTransparency: false, increaseContrast: false)
        #expect(look.usesSystemGlass)
        #expect(!look.drawsOutline)
    }

    @Test("Reduce Transparency gives a solid panel")
    func reduceTransparency() {
        let look = HorizonGlassLook.resolve(reduceTransparency: true, increaseContrast: false)
        #expect(!look.usesSystemGlass)
        #expect(!look.drawsOutline)
    }

    @Test("Increase Contrast adds an outline, with or without glass")
    func increaseContrast() {
        #expect(HorizonGlassLook.resolve(reduceTransparency: false, increaseContrast: true)
            .drawsOutline)
        let both = HorizonGlassLook.resolve(reduceTransparency: true, increaseContrast: true)
        #expect(both.drawsOutline)
        #expect(!both.usesSystemGlass)
    }

    @Test("Glass controls and panels render in both appearances and every look")
    @MainActor
    func rendersEveryLook() {
        for reduce in [false, true] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                let view = HStack {
                    Button("15 more minutes") {}.buttonStyle(.horizonGlass)
                    Button("Call it a day") {}.buttonStyle(.horizonGlassProminent)
                    Text("Panel").padding().horizonGlassPanel()
                }
                .environment(\._accessibilityReduceTransparency, reduce)
                .environment(\._colorSchemeContrast, contrast)
                let renderer = ImageRenderer(content: view)
                #expect(renderer.nsImage != nil)
            }
        }
    }
}
