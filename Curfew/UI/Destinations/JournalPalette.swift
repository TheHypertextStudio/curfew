import SwiftUI

/// The Journal's light "sundown" palette, shared by ``JournalSundownView`` and
/// ``JournalReflectionsView`` so the whole destination reads as one surface.
///
/// The app uses a deliberate light chrome (see commit history); these are the
/// warm paper/ink tones the Journal is composed from. Centralised here so the
/// week chart and the reflections below it can never drift apart.
enum JournalPalette {
    static let canvas = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let card = Color.white.opacity(0.55)
    static let ink = Color(red: 0.19, green: 0.16, blue: 0.14)
    static let inkSoft = Color(red: 0.52, green: 0.46, blue: 0.41)
    static let ember = Color(red: 0.85, green: 0.45, blue: 0.23)
    static let faint = Color.black.opacity(0.1)
}
