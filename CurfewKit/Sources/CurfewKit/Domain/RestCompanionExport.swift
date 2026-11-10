import Foundation

/// Bounded local-only presentation exchange for the optional rest companion.
/// This is neither a remote protocol nor a restriction-authority or account-sync envelope.
public nonisolated struct RestCompanionExport: Equatable, Sendable {
    public static let currentVersion = 1
    public static let maximumImageBytes = 2 * 1024 * 1024
    public static let maximumImageDimension = 3840
    public static let maximumEnvelopeBytes = 3 * 1024 * 1024

    /// An explicit allowlist prevents local image filenames and operational preferences escaping.
    public struct Appearance: Codable, Equatable, Sendable {
        public let background: RestAppearancePreferences.Background
        public let palette: RestAppearancePreferences.Palette
        public let solidRed: Double
        public let solidGreen: Double
        public let solidBlue: Double
        public let clockStyle: RestAppearancePreferences.ClockStyle
        public let clockPosition: RestAppearancePreferences.ClockPosition
        public let staticBackground: Bool
        public let message: String
        public let focalX: Double
        public let focalY: Double
        public let sunriseLeadMinutes: Int
    }

    /// Supplied by an ImageIO metadata-only adapter, never by fields in the wire payload.
    public struct ImageDimensions: Equatable, Sendable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    public enum ValidationError: Error, Equatable {
        case unsupportedVersion
        case envelopeTooLarge
        case imageTooLarge
        case invalidImageHeader
        case invalidImageDimensions
    }

    public let version: Int
    public let expiresAt: Date
    public let appearance: Appearance
    public let lockDate: Date?
    public let unlockDate: Date?
    public let imageData: Data?

    private struct Envelope: Codable {
        let version: Int
        let expiresAt: Date
        let appearance: Appearance
        let lockDate: Date?
        let unlockDate: Date?
        let imageData: Data?
    }

    /// Bounds encoded bytes before metadata inspection; the adapter must never decode pixels.
    public static func encode(
        snapshot: RestSceneSnapshot,
        imageData: Data?,
        inspectImageHeader: (Data) throws -> ImageDimensions
    ) throws -> Data {
        guard snapshot.version == currentVersion else {
            throw ValidationError.unsupportedVersion
        }
        try validate(imageData, inspectImageHeader: inspectImageHeader)
        let envelope = Envelope(
            version: currentVersion,
            expiresAt: snapshot.expiresAt,
            appearance: Appearance(
                preferences: snapshot.appearance,
                includeMessage: snapshot.appearance.saverMessageEnabled
            ),
            lockDate: snapshot.lockDate,
            unlockDate: snapshot.unlockDate,
            imageData: imageData
        )
        let encoder = JSONEncoder()
        // Avoid slash escaping inflating an otherwise bounded base64 image.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(envelope)
        guard bytes.count <= maximumEnvelopeBytes else {
            throw ValidationError.envelopeTooLarge
        }
        return bytes
    }

    /// Only a successfully returned export may reach a pixel-decoding visual adapter.
    public static func decode(
        _ bytes: Data,
        inspectImageHeader: (Data) throws -> ImageDimensions
    ) throws -> RestCompanionExport {
        guard bytes.count <= maximumEnvelopeBytes else {
            throw ValidationError.envelopeTooLarge
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
        guard envelope.version == currentVersion else {
            throw ValidationError.unsupportedVersion
        }
        try validate(envelope.imageData, inspectImageHeader: inspectImageHeader)
        return RestCompanionExport(
            version: envelope.version,
            expiresAt: envelope.expiresAt,
            appearance: envelope.appearance.normalized,
            lockDate: envelope.lockDate,
            unlockDate: envelope.unlockDate,
            imageData: envelope.imageData
        )
    }

    public func resolve(at now: Date, timeZone: TimeZone) -> RestSceneSnapshot.Frame {
        RestSceneSnapshot(
            version: version,
            expiresAt: expiresAt,
            appearance: appearance.preferences,
            lockDate: lockDate,
            unlockDate: unlockDate
        ).resolve(at: now, timeZone: timeZone)
    }

    private static func validate(
        _ imageData: Data?,
        inspectImageHeader: (Data) throws -> ImageDimensions
    ) throws {
        guard let imageData else { return }
        guard imageData.count <= maximumImageBytes else {
            throw ValidationError.imageTooLarge
        }
        let dimensions: ImageDimensions
        do {
            dimensions = try inspectImageHeader(imageData)
        } catch {
            throw ValidationError.invalidImageHeader
        }
        guard (1 ... maximumImageDimension).contains(dimensions.width),
              (1 ... maximumImageDimension).contains(dimensions.height)
        else { throw ValidationError.invalidImageDimensions }
    }
}

private extension RestCompanionExport.Appearance {
    init(preferences: RestAppearancePreferences, includeMessage: Bool) {
        background = preferences.background
        palette = preferences.palette
        solidRed = preferences.solidRed
        solidGreen = preferences.solidGreen
        solidBlue = preferences.solidBlue
        clockStyle = preferences.clockStyle
        clockPosition = preferences.clockPosition
        staticBackground = preferences.staticBackground
        message = includeMessage ? preferences.message : ""
        focalX = preferences.focalX
        focalY = preferences.focalY
        sunriseLeadMinutes = preferences.sunriseLeadMinutes
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
            focalX: focalX,
            focalY: focalY,
            sunriseLeadMinutes: sunriseLeadMinutes
        )
    }

    var normalized: Self {
        let values = preferences
        // Local image ownership is deliberately absent from the exchange. Preserve the
        // visual selection independently while reusing preference scalar sanitization.
        return Self(
            background: background,
            palette: values.palette,
            solidRed: values.solidRed,
            solidGreen: values.solidGreen,
            solidBlue: values.solidBlue,
            clockStyle: values.clockStyle,
            clockPosition: values.clockPosition,
            staticBackground: values.staticBackground,
            message: values.message,
            focalX: values.focalX,
            focalY: values.focalY,
            sunriseLeadMinutes: values.sunriseLeadMinutes
        )
    }
}
