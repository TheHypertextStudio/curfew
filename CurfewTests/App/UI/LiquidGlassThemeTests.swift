import AppKit
@testable import Curfew
@testable import CurfewKit
import SwiftUI
import Testing

@MainActor
struct LiquidGlassThemeTests {
    @Test("Liquid glass surface switches between translucent and opaque solid fallback")
    func liquidGlassAccessibilityFallback() throws {
        let aqua = try #require(NSAppearance(named: .aqua))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))

        for appearance in [aqua, darkAqua] {
            let solid = resolved(SundownPalette.glassSurface(usesSolidPanels: true), in: appearance)
            let translucent = resolved(
                SundownPalette.glassSurface(usesSolidPanels: false),
                in: appearance
            )

            #expect(solid.alphaComponent == 1.0)
            #expect(translucent.alphaComponent < 1.0)
            #expect(abs(translucent.alphaComponent - 0.60) < 0.01)
            #expect(
                SundownPalette.glassSurface(usesSolidPanels: true) ==
                    SundownPalette.inputSurface(usesSolidPanels: true)
            )
        }
    }

    @Test("Atmospheric text maintains contrast over translucent glass surface across appearances")
    func glassSurfaceTextContrast() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            let glass = SundownPalette.glassSurface(usesSolidPanels: false)

            for backdrop in [Color.white, CurfewTheme.canvas, CurfewTheme.canvasStrong] {
                let compositedGlass = composite(glass, over: backdrop, in: appearance)
                let primaryContrast = contrast(
                    SundownPalette.warmWhite,
                    compositedGlass,
                    in: appearance
                )
                let supportingContrast = contrast(
                    SundownPalette.supportingText,
                    compositedGlass,
                    in: appearance
                )

                #expect(
                    primaryContrast >= 4.5,
                    "Primary atmospheric text must meet 4.5:1 over glass on \(backdrop)"
                )
                #expect(
                    supportingContrast >= 4.0,
                    "Supporting atmospheric text must remain readable over glass on \(backdrop)"
                )
            }
        }
    }

    @Test("Liquid glass view modifiers produce renderable view hierarchies in both appearances")
    func liquidGlassModifiersRenderSuccessfully() {
        let card = Text("Card Content")
            .padding()
            .liquidGlassCard(cornerRadius: 16, usesSolidPanels: false)

        let solidCard = Text("Solid Card Content")
            .padding()
            .liquidGlassCard(cornerRadius: 16, usesSolidPanels: true)

        let capsule = Text("Capsule Pill")
            .padding()
            .liquidGlassCapsule(usesSolidPanels: false)

        let sidebar = Text("Sidebar Content")
            .padding()
            .sidebarGlass()

        for (name, view) in [
            ("card", AnyView(card)),
            ("solidCard", AnyView(solidCard)),
            ("capsule", AnyView(capsule)),
            ("sidebar", AnyView(sidebar))
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

    private func resolved(_ color: Color, in appearance: NSAppearance) -> NSColor {
        var value = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            value = NSColor(color).usingColorSpace(.sRGB) ?? .black
        }
        return value
    }

    private func composite(
        _ foreground: Color,
        over background: Color,
        in appearance: NSAppearance
    ) -> Color {
        let front = resolved(foreground, in: appearance)
        let back = resolved(background, in: appearance)
        let alpha = front.alphaComponent
        return Color(
            red: front.redComponent * alpha + back.redComponent * (1 - alpha),
            green: front.greenComponent * alpha + back.greenComponent * (1 - alpha),
            blue: front.blueComponent * alpha + back.blueComponent * (1 - alpha)
        )
    }

    private func contrast(
        _ foreground: Color,
        _ background: Color,
        in appearance: NSAppearance
    ) -> Double {
        func luminance(_ color: Color) -> Double {
            let res = resolved(color, in: appearance)
            let channels = [res.redComponent, res.greenComponent, res.blueComponent]
                .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        let first = luminance(composite(foreground, over: background, in: appearance))
        let second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
