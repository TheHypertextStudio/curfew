import CurfewKit
import SwiftUI

/// The Journal's palette, shared by ``JournalSundownView`` and
/// ``JournalReflectionsView`` so the whole destination reads as one surface.
///
/// These alias the app-wide ``CurfewTheme`` so every tone resolves adaptively
/// (Light / Dark Aqua) — the Journal must not pin a fixed light background, or
/// it blinds in Dark Mode. Centralised here so the week chart and the
/// reflections below it can never drift apart.
enum JournalPalette {
    static let canvas = CurfewTheme.canvas
    static let card = CurfewTheme.surface
    static let ink = CurfewTheme.ink
    static let inkSoft = CurfewTheme.mutedInk
    static let ember = CurfewTheme.accent
    static let faint = CurfewTheme.border
}
