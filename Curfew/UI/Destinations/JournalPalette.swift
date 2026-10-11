import CurfewKit
import SwiftUI

/// The Journal's light "sundown" palette, shared by ``JournalSundownView`` and
/// ``JournalReflectionsView`` so the whole destination reads as one surface.
///
/// The app uses a deliberate light chrome (see commit history); these are the
/// warm paper/ink tones the Journal is composed from. Centralised here so the
/// week chart and the reflections below it can never drift apart.
enum JournalPalette {
    static let canvas = SundownPalette.paper
    static let card = Color.white.opacity(0.55)
    static let ink = SundownPalette.ink
    static let inkSoft = SundownPalette.inkSoft
    static let ember = SundownPalette.ember
    static let faint = Color.black.opacity(0.1)
}
