import AppKit
@testable import Curfew
@testable import CurfewKit
import SwiftUI
import Testing

@MainActor
struct ThemeConsistencyTests {
    @Test("Capture settings never construct real account or camera services")
    func settingsFixtureIsolation() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let settings = try String(contentsOf: root.appendingPathComponent(
            "Curfew/UI/SettingsView.swift"
        ), encoding: .utf8)
        #expect(settings.contains("AccountEnrollmentController.settingsController()"))
        let presence = try String(contentsOf: root.appendingPathComponent(
            "Curfew/App/Model/CurfewAppModel+Presence.swift"
        ), encoding: .utf8)
        #expect(presence.contains("isDemoSession ? DemoPresenceSensor()"))
        #expect(presence.contains("guard !isDemoSession, !RuntimeEnvironment.isUnitTestHost"))
    }

    @Test("Body, supporting text, and links remain readable on shared surfaces")
    func textContrast() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            for background in [
                CurfewTheme.canvas,
                CurfewTheme.canvasStrong,
                CurfewTheme.surface,
                CurfewTheme.surfaceMuted
            ] {
                for foreground in [
                    CurfewTheme.ink,
                    CurfewTheme.mutedInk,
                    CurfewTheme.accent,
                    CurfewTheme.warning
                ] {
                    #expect(contrast(foreground, background, appearance: appearance) >= 4.5)
                }
            }
        }
    }

    @Test("Settings, workspace, and atmospheric controls share semantic colors")
    func sharedPalette() throws {
        let root = URL(fileURLWithPath: #filePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let settings = try String(contentsOf: root.appendingPathComponent(
            "Curfew/UI/SettingsView.swift"
        ), encoding: .utf8)
        #expect(settings.contains(".background(CurfewTheme.canvasStrong)"))
        #expect(settings.contains(".background(CurfewTheme.canvas)"))
        #expect(!settings.contains(".tint(.gray)"))
        #expect(
            !settings.contains("        .foregroundStyle(CurfewTheme.ink)"),
            "Do not override native selected-row foreground"
        )
        for path in [
            "Curfew/UI/SettingsView+InfoPanels.swift",
            "Curfew/UI/SettingsView+EnforcementPanels.swift"
        ] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            #expect(
                !source.contains(".foregroundStyle(.secondary)"),
                "Supporting text must use the contrast-checked palette"
            )
        }
        let sky = try String(contentsOf: root.appendingPathComponent(
            "Curfew/UI/Sundown/SundownPalette.swift"
        ), encoding: .utf8)
        #expect(sky.contains("static let ember = CurfewTheme.accentFill"))
        let theme = try String(contentsOf: root.appendingPathComponent(
            "Curfew/UI/CurfewTheme.swift"
        ), encoding: .utf8)
        #expect(theme.contains(".fill(CurfewTheme.accentFill)"))
    }

    @Test("Every Settings section participates in the native grouped form")
    func settingsSectionsDoNotNestDecorativeCards() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for name in ["EnforcementPanels", "PresencePanel", "SyncPanel", "TaskBrowserEnforcement"] {
            let source = try String(
                contentsOf: root.appendingPathComponent("Curfew/UI/SettingsView+\(name).swift"),
                encoding: .utf8
            )
            #expect(
                !source.contains("CurfewPanel {"),
                "\(name) must share the Settings form hierarchy"
            )
        }
    }

    @Test("Filled actions preserve white-label contrast in both appearances")
    func filledActionContrast() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            #expect(
                contrast(CurfewTheme.onAccent, CurfewTheme.accentFill, appearance: appearance) >=
                    4.5
            )
        }
    }

    @Test("Atmospheric labels remain readable across the opaque night gradient")
    func atmosphericContrast() throws {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        for stop in SundownPalette.skyStops(for: 0) {
            #expect(contrast(SundownPalette.warmWhite, stop.color, appearance: appearance) >= 4.5)
            #expect(contrast(SundownPalette.supportingText, stop.color, appearance: appearance) >=
                4.5)
            #expect(contrast(SundownPalette.glow, stop.color, appearance: appearance) >= 3)
        }
    }

    @Test("Reflection input text stays readable even over a white backdrop")
    func reflectionInputContrast() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            for solid in [false, true] {
                let input = composite(
                    SundownPalette.inputSurface(usesSolidPanels: solid),
                    over: .white,
                    appearance: appearance
                )
                #expect(contrast(SundownPalette.warmWhite, input, appearance: appearance) >= 4.5)
                #expect(contrast(SundownPalette.supportingText, input, appearance: appearance) >=
                    4.5)
            }
        }
    }

    @Test("Hold-progress wash preserves filled-action label contrast")
    func progressContrast() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            let progressed = composite(
                CurfewTheme.filledProgressOverlay,
                over: CurfewTheme.accentFill,
                appearance: appearance
            )
            #expect(contrast(CurfewTheme.onAccent, progressed, appearance: appearance) >= 4.5)
        }
    }

    @Test("Native selection assets match shared filled controls in each appearance")
    func nativeAccentConsistency() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let file = root
            .appendingPathComponent("Curfew/Assets.xcassets/AccentColor.colorset/Contents.json")
        let asset = try JSONDecoder().decode(AccentAsset.self, from: Data(contentsOf: file))
        for entry in asset.colors {
            let isDark = entry.appearances?.contains { $0.value == "dark" } ?? false
            let appearance = try #require(NSAppearance(named: isDark ? .darkAqua : .aqua))
            let components = entry.color.components
            let native = try Color(
                red: #require(Double(components.red)),
                green: #require(Double(components.green)),
                blue: #require(Double(components.blue))
            )
            let nativeColor = resolved(native, appearance: appearance)
            let filledColor = resolved(CurfewTheme.accentFill, appearance: appearance)
            #expect(abs(nativeColor.redComponent - filledColor.redComponent) < 0.001)
            #expect(abs(nativeColor.greenComponent - filledColor.greenComponent) < 0.001)
            #expect(abs(nativeColor.blueComponent - filledColor.blueComponent) < 0.001)
        }
    }

    @Test("Views consume palette roles instead of embedding RGB colors")
    func noViewColorLiterals() throws {
        let root = URL(fileURLWithPath: #filePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Curfew")
        let files = try #require(FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ))
        let explicitHue = #"(Color\.|foregroundStyle\(\.)(green|red|orange|blue|purple|yellow)\b"#
        let palettes = ["CurfewTheme.swift", "SundownPalette.swift"]
        for case let file as URL in files where file.pathExtension == "swift" {
            guard !palettes.contains(file.lastPathComponent) else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(
                !source.contains(".foregroundStyle(.secondary)"),
                "Use the contrast-checked supporting-text role"
            )
            #expect(
                source
                    .range(
                        of: explicitHue,
                        options: .regularExpression
                    ) == nil,
                "Use shared semantic roles in \(file.lastPathComponent)"
            )
            if file.lastPathComponent == "ReflectionFormView.swift" {
                #expect(
                    !source.contains(".foregroundStyle(.white.opacity"),
                    "Reflection text must use shared atmospheric text roles"
                )
            }
            #expect(
                source.range(
                    of: #"(?:NS)?Color\s*\(\s*red:"#,
                    options: .regularExpression
                ) == nil,
                "Move RGB literals from \(file.lastPathComponent) to the shared palette"
            )
        }
    }

    private func resolved(_ color: Color, appearance: NSAppearance) -> NSColor {
        var value = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            value = NSColor(color).usingColorSpace(.sRGB) ?? .black
        }
        return value
    }

    private func composite(
        _ foreground: Color,
        over background: Color,
        appearance: NSAppearance
    ) -> Color {
        let front = resolved(foreground, appearance: appearance)
        let back = resolved(background, appearance: appearance)
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
        appearance: NSAppearance
    ) -> Double {
        func luminance(_ color: Color) -> Double {
            let resolved = resolved(color, appearance: appearance)
            let channels = [resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
                .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        let first = luminance(composite(foreground, over: background, appearance: appearance))
        let second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}

extension ThemeConsistencyTests {
    @Test("Override input binds readable atmospheric text and surface roles")
    func overrideInputPalette() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Curfew/UI/LockoutScreenView.swift"
        ), encoding: .utf8)
        let editor = try #require(source.components(separatedBy:
            "TextEditor(text: $model.overrideReasonDraft)").last)
            .components(separatedBy: "Text(").first ?? ""
        #expect(editor.contains(".foregroundStyle(SundownPalette.warmWhite)"))
        #expect(editor.contains("SundownPalette.inputSurface("))
    }
}

private struct AccentAsset: Decodable {
    let colors: [AccentEntry]
}

private struct AccentEntry: Decodable {
    let color: AccentValue
    let appearances: [AccentAppearance]?
}

private struct AccentAppearance: Decodable {
    let value: String
}

private struct AccentValue: Decodable {
    let components: AccentComponents
}

private struct AccentComponents: Decodable {
    let red: String
    let green: String
    let blue: String
}
