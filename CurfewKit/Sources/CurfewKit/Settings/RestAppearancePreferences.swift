import Foundation

// TEMPORARY TDD scaffold: no normalization or migration decoding yet.
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
        self.background = background
        self.palette = palette
        self.solidRed = solidRed
        self.solidGreen = solidGreen
        self.solidBlue = solidBlue
        self.clockStyle = clockStyle
        self.clockPosition = clockPosition
        self.staticBackground = staticBackground
        self.message = message
        self.ownedImageFilename = ownedImageFilename
        self.focalX = focalX
        self.focalY = focalY
        self.saverMessageEnabled = saverMessageEnabled
        self.sunriseWakeEnabled = sunriseWakeEnabled
        self.sunriseLeadMinutes = sunriseLeadMinutes
        self.sunriseOnBatteryEnabled = sunriseOnBatteryEnabled
    }
}
