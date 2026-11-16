import CurfewKit
import SwiftUI

/// The type scale. One family, San Francisco: the rounded design for numerals,
/// headlines and buttons, the default design for body text. No serif and no
/// spaced capitals.
///
/// Prefer ``View/sundownFont(_:size:)``: it scales the size with the system
/// text size, relative to the role's text style. The static functions return
/// a fixed-size font for call sites that have not moved to it yet.
enum SundownType {
    /// A type role: weight, design and the text style its size scales with.
    enum Role: CaseIterable, Sendable {
        /// Hero numerals (the countdown, the clock).
        case display
        /// Metric figures.
        case figure
        /// Section headlines.
        case headline
        /// Decisions and sub-headers.
        case title
        /// Button labels.
        case button
        /// Reading text.
        case body
        /// A single emphasised value inside otherwise-regular text.
        case strong
        /// Small sentence-case captions.
        case label

        var weight: Font.Weight {
            switch self {
            case .display, .title, .button: .semibold
            case .figure, .headline: .bold
            case .body: .regular
            case .strong, .label: .medium
            }
        }

        var design: Font.Design {
            switch self {
            case .display, .figure, .headline, .title, .button: .rounded
            case .body, .strong, .label: .default
            }
        }

        /// The system text style the size scales relative to.
        var relativeTo: Font.TextStyle? {
            switch self {
            case .display, .figure: .largeTitle
            case .headline: .title
            case .title: .title3
            case .button, .strong: .headline
            case .body: .body
            case .label: .caption
            }
        }

        func font(size: CGFloat) -> Font {
            .system(size: size, weight: weight, design: design)
        }
    }

    static func display(_ size: CGFloat) -> Font {
        Role.display.font(size: size)
    }

    static func headline(_ size: CGFloat = 28) -> Font {
        Role.headline.font(size: size)
    }

    static func figure(_ size: CGFloat) -> Font {
        Role.figure.font(size: size)
    }

    static func title(_ size: CGFloat = 18) -> Font {
        Role.title.font(size: size)
    }

    static func button(_ size: CGFloat = 15) -> Font {
        Role.button.font(size: size)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        Role.body.font(size: size)
    }

    static func strong(_ size: CGFloat = 15) -> Font {
        Role.strong.font(size: size)
    }

    static func label(_ size: CGFloat = 12) -> Font {
        Role.label.font(size: size)
    }
}

extension View {
    /// Sets a type role at a base size that scales with the system text size.
    /// Use `.monospacedDigit()` only where numbers align in columns.
    func sundownFont(_ role: SundownType.Role, size: CGFloat) -> some View {
        modifier(SundownScaledFont(role: role, base: size))
    }
}

private struct SundownScaledFont: ViewModifier {
    let role: SundownType.Role
    @ScaledMetric private var size: CGFloat

    init(role: SundownType.Role, base: CGFloat) {
        self.role = role
        _size = ScaledMetric(wrappedValue: base, relativeTo: role.relativeTo ?? .body)
    }

    func body(content: Content) -> some View {
        content.font(role.font(size: size))
    }
}
