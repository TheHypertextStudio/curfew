import SwiftUI

/// Foreground roles shared by the rest scene and its hosts. The sky's own
/// colours live in ``HorizonPalette``.
public enum AtmospherePalette {
    /// Warm foreground shared by atmospheric hosts and the renderer.
    public static let warmWhite = Color(red: 0.99, green: 0.97, blue: 0.94)
    /// Shields atmospheric text over a photograph or a chosen colour.
    public static let textScrim = Color.black.opacity(0.72)

    /// User-selected solid background, preserving its stored RGB components.
    public static func solidBackground(red: Double, green: Double, blue: Double) -> Color {
        Color(red: red, green: green, blue: blue)
    }
}
