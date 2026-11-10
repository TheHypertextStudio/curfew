import Foundation

/// Normalized appearance and opt-in Sunrise preferences that remain local to this Mac.
public nonisolated struct RestAppearancePreferences: Codable, Equatable, Sendable {
    public enum Background: String, Codable, Sendable {
        case atmosphere, solid, image
    }

    public enum Palette: String, Codable, Sendable {
        case sundown, warmAmber, coolTwilight
    }

    public enum ClockStyle: String, Codable, Sendable {
        case rounded, standard, serif
    }

    public enum ClockPosition: String, Codable, Sendable {
        case center, upperCenter, lowerLeft
    }

    public let background: Background
    public let palette: Palette
    public let solidRed: Double
    public let solidGreen: Double
    public let solidBlue: Double
    public let clockStyle: ClockStyle
    public let clockPosition: ClockPosition
    public let staticBackground: Bool
    public let message: String
    public let ownedImageFilename: String?
    public let focalX: Double
    public let focalY: Double
    public let saverMessageEnabled: Bool
    public let sunriseWakeEnabled: Bool
    public let sunriseLeadMinutes: Int
    public let sunriseOnBatteryEnabled: Bool

    public init(
        background: Background = .atmosphere,
        palette: Palette = .sundown,
        solidRed: Double = 0.06,
        solidGreen: Double = 0.07,
        solidBlue: Double = 0.15,
        clockStyle: ClockStyle = .rounded,
        clockPosition: ClockPosition = .center,
        staticBackground: Bool = false,
        message: String = "",
        ownedImageFilename: String? = nil,
        focalX: Double = 0.5,
        focalY: Double = 0.5,
        saverMessageEnabled: Bool = false,
        sunriseWakeEnabled: Bool = false,
        sunriseLeadMinutes: Int = 30,
        sunriseOnBatteryEnabled: Bool = false
    ) {
        let imageFilename = Self.validatedImageFilename(ownedImageFilename)
        self.background = background == .image && imageFilename == nil ? .atmosphere : background
        self.palette = palette
        self.solidRed = Self.unitValue(solidRed, fallback: 0.06)
        self.solidGreen = Self.unitValue(solidGreen, fallback: 0.07)
        self.solidBlue = Self.unitValue(solidBlue, fallback: 0.15)
        self.clockStyle = clockStyle
        self.clockPosition = clockPosition
        self.staticBackground = staticBackground
        self.message = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
        self.ownedImageFilename = imageFilename
        self.focalX = Self.unitValue(focalX, fallback: 0.5)
        self.focalY = Self.unitValue(focalY, fallback: 0.5)
        self.saverMessageEnabled = saverMessageEnabled
        self.sunriseWakeEnabled = sunriseWakeEnabled
        self.sunriseLeadMinutes = min(60, max(5, sunriseLeadMinutes))
        self.sunriseOnBatteryEnabled = sunriseOnBatteryEnabled
    }

    /// Module-internal bridge from the validated export allowlist. Image pixels belong to
    /// that export, so preserving `.image` must not manufacture a local owned filename.
    init(presentationAppearance: RestCompanionExport.Appearance) {
        self.background = presentationAppearance.background
        self.palette = presentationAppearance.palette
        self.solidRed = presentationAppearance.solidRed
        self.solidGreen = presentationAppearance.solidGreen
        self.solidBlue = presentationAppearance.solidBlue
        self.clockStyle = presentationAppearance.clockStyle
        self.clockPosition = presentationAppearance.clockPosition
        self.staticBackground = presentationAppearance.staticBackground
        self.message = presentationAppearance.message
        self.ownedImageFilename = nil
        self.focalX = presentationAppearance.focalX
        self.focalY = presentationAppearance.focalY
        self.saverMessageEnabled = false
        self.sunriseWakeEnabled = false
        self.sunriseLeadMinutes = presentationAppearance.sunriseLeadMinutes
        self.sunriseOnBatteryEnabled = false
    }

    private enum CodingKeys: String, CodingKey {
        case background, palette, solidRed, solidGreen, solidBlue
        case clockStyle, clockPosition, staticBackground, message, ownedImageFilename
        case focalX, focalY, saverMessageEnabled
        case sunriseWakeEnabled, sunriseLeadMinutes, sunriseOnBatteryEnabled
    }

    /// Missing or malformed fields migrate independently, retaining valid sibling choices.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            background: (try? container.decode(Background.self, forKey: .background)) ??
                .atmosphere,
            palette: (try? container.decode(Palette.self, forKey: .palette)) ?? .sundown,
            solidRed: (try? container.decode(Double.self, forKey: .solidRed)) ?? 0.06,
            solidGreen: (try? container.decode(Double.self, forKey: .solidGreen)) ?? 0.07,
            solidBlue: (try? container.decode(Double.self, forKey: .solidBlue)) ?? 0.15,
            clockStyle: (try? container.decode(ClockStyle.self, forKey: .clockStyle)) ?? .rounded,
            clockPosition: (try? container.decode(ClockPosition.self, forKey: .clockPosition)) ??
                .center,
            staticBackground: (try? container.decode(Bool.self, forKey: .staticBackground)) ??
                false,
            message: (try? container.decode(String.self, forKey: .message)) ?? "",
            ownedImageFilename: try? container.decode(String.self, forKey: .ownedImageFilename),
            focalX: (try? container.decode(Double.self, forKey: .focalX)) ?? 0.5,
            focalY: (try? container.decode(Double.self, forKey: .focalY)) ?? 0.5,
            saverMessageEnabled: (try? container.decode(Bool.self, forKey: .saverMessageEnabled)) ??
                false,
            sunriseWakeEnabled: (try? container.decode(Bool.self, forKey: .sunriseWakeEnabled)) ??
                false,
            sunriseLeadMinutes: (try? container.decode(Int.self, forKey: .sunriseLeadMinutes)) ??
                30,
            sunriseOnBatteryEnabled: (try? container.decode(
                Bool.self,
                forKey: .sunriseOnBatteryEnabled
            )) ?? false
        )
    }

    private static func unitValue(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : fallback
    }

    private static func validatedImageFilename(_ filename: String?) -> String? {
        guard let filename else { return nil }
        let parts = filename.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              ["jpg", "png", "heic"].contains(String(parts[1])),
              let identifier = UUID(uuidString: String(parts[0])),
              identifier.uuidString.lowercased() == parts[0].lowercased()
        else { return nil }
        return filename
    }
}
