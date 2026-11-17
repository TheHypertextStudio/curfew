import CurfewAtmosphere
import CurfewKit
import SwiftUI

extension RestAppearancePreferences.ClockStyle {
    /// The face the clock is drawn in.
    var fontDesign: Font.Design {
        switch self {
        case .rounded: .rounded
        case .standard: .default
        case .serif: .serif
        }
    }
}

/// Puts the person's theme into the environment of a window's root, so every
/// sky inside it draws their palette. A modifier rather than a value, so a
/// window built once (an `NSHostingView`) follows later changes.
private struct CurfewThemeEnvironment: ViewModifier {
    let model: CurfewAppModel

    func body(content: Content) -> some View {
        content.environment(\.horizonPalette, model.horizonPalette)
    }
}

extension View {
    /// Draws every sky in this view in the person's chosen palette.
    func curfewTheme(_ model: CurfewAppModel) -> some View {
        modifier(CurfewThemeEnvironment(model: model))
    }
}
