import Foundation

/// Proposed local-only presentation exchange. Intentionally inert pending observed behavioral RED.
/// This is neither a remote protocol nor a restriction-authority or account-sync envelope.
public nonisolated struct RestCompanionExport: Equatable, Sendable {
    public static let currentVersion = 1
    public static let maximumImageBytes = 2 * 1024 * 1024
    public static let maximumImageDimension = 3840
    public static let maximumEnvelopeBytes = 3 * 1024 * 1024

    /// An explicit allowlist prevents local image filenames and operational preferences escaping.
    public struct Appearance: Equatable, Sendable {
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
        case notImplemented
    }

    public let version: Int
    public let expiresAt: Date
    public let appearance: Appearance
    public let lockDate: Date?
    public let unlockDate: Date?
    public let imageData: Data?

    /// Future implementation must bound bytes before metadata inspection and sanitize opt-in text.
    /// Header inspection must not decode image pixels. No native or filesystem API is used here.
    public static func encode(
        snapshot _: RestSceneSnapshot,
        imageData _: Data?,
        inspectImageHeader _: (Data) throws -> ImageDimensions
    ) throws -> Data {
        throw ValidationError.notImplemented
    }

    /// Future implementation independently validates the complete envelope and image headers.
    /// Only a successfully returned export may pass imageData to a pixel-decoding visual adapter.
    public static func decode(
        _: Data,
        inspectImageHeader _: (Data) throws -> ImageDimensions
    ) throws -> RestCompanionExport {
        throw ValidationError.notImplemented
    }

    /// Inert neutral return. Future resolution must preserve RestSceneSnapshot expiry semantics.
    public func resolve(at _: Date, timeZone _: TimeZone) -> RestSceneSnapshot.Frame {
        RestSceneSnapshot.Frame(phase: .allDay, sunriseProgress: 0)
    }
}
