import SwiftUI

/// Intentional type scale for the sundown design language (proposal).
///
/// Built on the system font (SF Pro) — native, modern, and it gives Dynamic
/// Type and optical sizing for free. Numerals use the rounded design (clock-
/// like, warm); everything else uses the default design (clean).
///
/// "Bolder" by **range**, not by blanket weight: a substantial Semibold hero,
/// Bold headlines and figures, and restrained Regular/Medium for everything
/// supporting. Weight is a hierarchy tool — earned by headlines and numbers,
/// withheld from body and labels.
enum SundownType {
    /// Hero numerals (the countdown). Substantial weight + scale — confident,
    /// never wispy.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    /// Section headlines — the deliberate step up in confidence.
    static func headline(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold)
    }

    /// Punchy data — metric counts that should read as an achievement.
    static func figure(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    /// Decisions and sub-headers — present, but not headline-loud.
    static func title(_ size: CGFloat = 18) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// Reading text.
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }

    /// A single emphasised value inside otherwise-regular text.
    static func strong(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium)
    }

    /// Small uppercase eyebrows / captions. Used sparingly.
    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium)
    }
}
