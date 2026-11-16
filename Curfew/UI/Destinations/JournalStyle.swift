import AppKit
import SwiftUI

/// The Journal's colours, type and shapes.
///
/// The page follows the system appearance on the app's paper and ink tokens
/// with ember as the only accent. Data marks use the chart colours validated
/// for colour-blind separation in the launch design; text never takes a data
/// colour, so every coloured mark sits beside text in ink.
enum JournalStyle {
    // MARK: - Page

    static let page = CurfewTheme.surface
    static let ink = CurfewTheme.ink
    static let soft = CurfewTheme.mutedInk
    static let accent = CurfewTheme.accent
    /// Tile and hover fill.
    static let chip = CurfewTheme.surfaceMuted
    /// Card borders and table rules.
    static let line = adaptive(light: 0xE3DED7, dark: 0x3D3835)
    /// Chart gridlines, quieter than card borders.
    static let grid = adaptive(light: 0xEBE6DF, dark: 0x353130)
    /// Strokes for hollow marks. Never used for text.
    static let faint = adaptive(light: 0x8F857C, dark: 0x8C8178)
    static let tipBackground = CurfewTheme.ink
    static let tipForeground = CurfewTheme.surface

    // MARK: - Data

    static let early = adaptive(light: 0x2F62C8, dark: 0x5F8FE8)
    static let atCurfew = adaptive(light: 0x9A958E, dark: 0x7D766F)
    static let over = adaptive(light: 0xC9521D, dark: 0xDD6C3A)
    static let early1 = adaptive(light: 0x8AABE7, dark: 0x41609F)
    static let early2 = adaptive(light: 0x5A84D8, dark: 0x5078CC)
    static let over1 = adaptive(light: 0xE79F78, dark: 0x8A4326)
    static let over2 = adaptive(light: 0xDA7644, dark: 0xB85A32)
    /// Figures printed on a filled data segment.
    static let onEarly = adaptive(light: 0xFFFFFF, dark: 0x14120F)
    static let onAtCurfew = adaptive(light: 0x1D1A18, dark: 0xFFFFFF)
    static let onOver = adaptive(light: 0xFFFFFF, dark: 0x14120F)

    static func color(_ mark: JournalMark) -> Color {
        switch mark {
        case .early: early
        case .atCurfew: atCurfew
        case .over: over
        }
    }

    static func color(_ bin: JournalHeatBin) -> Color {
        switch bin {
        case .early3: early
        case .early2: early2
        case .early1: early1
        case .atCurfew: atCurfew
        case .over1: over1
        case .over2: over2
        case .over3: over
        case .noRecord: chip
        }
    }

    // MARK: - Shape and space

    static let controlRadius: CGFloat = 8
    static let panelRadius: CGFloat = 20
    /// Widest the reading column grows.
    static let contentWidth: CGFloat = 992

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// The Journal's type roles. System font throughout; the rounded design for
/// numerals, headlines and buttons. Sizes follow the system text size.
enum JournalFont {
    case title
    case headline
    case section
    case cardTitle
    case statement
    case figure
    case body
    case row
    case caption
    case small
    case axis
    case axisStrong
    case button

    private struct Spec {
        let size: CGFloat
        let weight: Font.Weight
        let rounded: Bool

        init(_ size: CGFloat, _ weight: Font.Weight, _ rounded: Bool) {
            self.size = size
            self.weight = weight
            self.rounded = rounded
        }
    }

    private var spec: Spec {
        switch self {
        case .title: Spec(30, .semibold, true)
        case .headline: Spec(26, .semibold, true)
        case .section: Spec(17, .semibold, true)
        case .cardTitle, .statement: Spec(15, .semibold, true)
        case .figure: Spec(26, .semibold, true)
        case .body: Spec(14, .regular, false)
        case .row: Spec(13, .regular, false)
        case .caption: Spec(12, .regular, false)
        case .small: Spec(11.5, .regular, false)
        case .axis: Spec(11, .medium, false)
        case .axisStrong: Spec(11, .semibold, true)
        case .button: Spec(13, .semibold, true)
        }
    }

    func font(scale: CGFloat) -> Font {
        let spec = spec
        return .system(
            size: spec.size * scale,
            weight: spec.weight,
            design: spec.rounded ? .rounded : .default
        )
    }

    private static let scales: [DynamicTypeSize: CGFloat] = [
        .xSmall: 0.86, .small: 0.92, .medium: 0.96, .large: 1,
        .xLarge: 1.1, .xxLarge: 1.2, .xxxLarge: 1.3,
        .accessibility1: 1.5, .accessibility2: 1.7, .accessibility3: 1.9,
        .accessibility4: 2.1, .accessibility5: 2.3
    ]

    /// How much the system text size scales the Journal's type.
    static func scale(for size: DynamicTypeSize) -> CGFloat {
        scales[size] ?? 1
    }
}

private struct JournalFontModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    let role: JournalFont

    func body(content: Content) -> some View {
        content.font(role.font(scale: JournalFont.scale(for: size)))
    }
}

extension View {
    func journalFont(_ role: JournalFont) -> some View {
        modifier(JournalFontModifier(role: role))
    }
}

/// A bordered panel at the panel radius.
struct JournalCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: JournalStyle.panelRadius, style: .continuous)
                .strokeBorder(JournalStyle.line, lineWidth: 1)
        )
    }
}

/// A small key swatch beside legend text.
struct JournalSwatch: View {
    let color: Color
    var isLine = false

    var body: some View {
        RoundedRectangle(cornerRadius: isLine ? 1.5 : 3, style: .continuous)
            .fill(color)
            .frame(width: 10, height: isLine ? 3 : 10)
            .frame(height: 10)
    }
}
