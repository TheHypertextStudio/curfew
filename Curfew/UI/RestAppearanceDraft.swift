import CurfewKit

/// Editing state preserves spaces while the persisted value is normalized.
struct RestAppearanceDraft: Equatable {
    var background: RestAppearancePreferences.Background
    var palette: RestAppearancePreferences.Palette
    var solidRed: Double
    var solidGreen: Double
    var solidBlue: Double
    var clockStyle: RestAppearancePreferences.ClockStyle
    var clockPosition: RestAppearancePreferences.ClockPosition
    var staticBackground: Bool
    var message: String
    var ownedImageFilename: String?
    var focalX: Double
    var focalY: Double
    var saverMessageEnabled: Bool
    var sunriseWakeEnabled: Bool
    var sunriseLeadMinutes: Int
    var sunriseOnBatteryEnabled: Bool

    init(_ value: RestAppearancePreferences) {
        self.background = value.background
        self.palette = value.palette
        self.solidRed = value.solidRed
        self.solidGreen = value.solidGreen
        self.solidBlue = value.solidBlue
        self.clockStyle = value.clockStyle
        self.clockPosition = value.clockPosition
        self.staticBackground = value.staticBackground
        self.message = value.message
        self.ownedImageFilename = value.ownedImageFilename
        self.focalX = value.focalX
        self.focalY = value.focalY
        self.saverMessageEnabled = value.saverMessageEnabled
        self.sunriseWakeEnabled = value.sunriseWakeEnabled
        self.sunriseLeadMinutes = value.sunriseLeadMinutes
        self.sunriseOnBatteryEnabled = value.sunriseOnBatteryEnabled
    }

    var preferences: RestAppearancePreferences {
        RestAppearancePreferences(
            background: background,
            palette: palette,
            solidRed: solidRed,
            solidGreen: solidGreen,
            solidBlue: solidBlue,
            clockStyle: clockStyle,
            clockPosition: clockPosition,
            staticBackground: staticBackground,
            message: message,
            ownedImageFilename: ownedImageFilename,
            focalX: focalX,
            focalY: focalY,
            saverMessageEnabled: saverMessageEnabled,
            sunriseWakeEnabled: sunriseWakeEnabled,
            sunriseLeadMinutes: sunriseLeadMinutes,
            sunriseOnBatteryEnabled: sunriseOnBatteryEnabled
        )
    }
}
