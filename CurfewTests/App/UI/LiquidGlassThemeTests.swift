import AppKit
@testable import Curfew
@testable import CurfewKit
import SwiftUI
import Testing

@MainActor
struct LiquidGlassThemeTests {
    @Test("System glass modifiers produce renderable view hierarchies in both appearances")
    func liquidGlassModifiersRenderSuccessfully() {
        let card = Text("Card Content")
            .padding()
            .horizonGlassPanel()

        let solidCard = Text("Solid Card Content")
            .padding()
            .horizonGlassPanel()
            .environment(\._accessibilityReduceTransparency, true)

        let capsule = Text("Capsule Pill")
            .padding()
            .horizonGlass(in: Capsule())

        for (name, view) in [
            ("card", AnyView(card)),
            ("solidCard", AnyView(solidCard)),
            ("capsule", AnyView(capsule))
        ] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let rendered = renderToImage(view, appearance: appearance)
                #expect(
                    rendered != nil,
                    "View '\(name)' with liquid glass modifier must render in \(appearance.rawValue)"
                )
                #expect(
                    (rendered?.size.width ?? 0) > 0,
                    "View '\(name)' must have positive width when rendered in \(appearance.rawValue)"
                )
            }
        }
    }

    @Test("Lockout visual configuration maps accessibility reduction flags deterministically")
    func lockoutVisualConfigurationMapping() {
        let standard = LockoutVisualConfiguration.resolve(
            reduceMotion: false,
            reduceTransparency: false
        )
        #expect(standard.animateBackground == true)
        #expect(standard.usesSolidPanels == false)

        let motionReduced = LockoutVisualConfiguration.resolve(
            reduceMotion: true,
            reduceTransparency: false
        )
        #expect(motionReduced.animateBackground == false)
        #expect(motionReduced.usesSolidPanels == false)

        let transparencyReduced = LockoutVisualConfiguration.resolve(
            reduceMotion: false,
            reduceTransparency: true
        )
        #expect(transparencyReduced.animateBackground == true)
        #expect(transparencyReduced.usesSolidPanels == true)

        let bothReduced = LockoutVisualConfiguration.resolve(
            reduceMotion: true,
            reduceTransparency: true
        )
        #expect(bothReduced.animateBackground == false)
        #expect(bothReduced.usesSolidPanels == true)
    }

    // MARK: - Color and Rendering Test Helpers

    private func renderToImage(
        _ view: some View,
        appearance: NSAppearance.Name
    ) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        var result: NSImage?
        if let app = NSAppearance(named: appearance) {
            app.performAsCurrentDrawingAppearance {
                result = renderer.nsImage
            }
        }
        return result
    }
}
