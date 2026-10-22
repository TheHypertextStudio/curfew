import CoreGraphics
import CurfewKit
import Foundation
import ImageIO
import ScreenSaver
import UniformTypeIdentifiers

/// Module-specific presentation exchange. Actual host readback is a separate acceptance gate.
public final class RestScreenSaverPreferences {
    public static let moduleIdentifier = "studio.hypertext.apps.curfew.screensaver"

    enum Keys {
        static let appearance = "rest.presentation.v1.appearance"
        static let occurrence = "rest.presentation.v1.occurrence"
        static let readbackRequest = "rest.presentation.v1.readbackRequest"
        static let acknowledgement = "rest.presentation.v1.acknowledgement"
    }

    public enum AdapterError: Error {
        case unavailable
        case persistenceRejected
        case stalePublication
    }

    private let defaults: UserDefaults
    private let store: RestCompanionPresentationStore

    public init(
        defaults: UserDefaults,
        inspectImageHeader: @escaping (Data) throws -> RestCompanionExport
            .ImageDimensions = RestScreenSaverPreferences.inspectImageHeader
    ) {
        self.defaults = defaults
        self.store = RestCompanionPresentationStore(
            read: { slot, maximum in
                guard let bytes = defaults.object(forKey: Self.key(for: slot)) as? Data,
                      bytes.count <= maximum else { return nil }
                return bytes
            },
            write: { slot, bytes in
                defaults.set(bytes, forKey: Self.key(for: slot))
                guard defaults.synchronize() else { throw AdapterError.persistenceRejected }
            },
            inspectImageHeader: inspectImageHeader
        )
    }

    /// The companion's bundle identifier scopes ScreenSaverDefaults; no App Group is assumed.
    public static func system() throws -> RestScreenSaverPreferences {
        guard let defaults = ScreenSaverDefaults(forModuleWithName: moduleIdentifier) else {
            throw AdapterError.unavailable
        }
        return RestScreenSaverPreferences(defaults: defaults)
    }

    public func publish(snapshot: RestSceneSnapshot, imageData: Data?) throws {
        defaults.synchronize()
        try store.publish(snapshot: snapshot, imageData: imageData)
    }

    public func read(at date: Date) -> RestCompanionPresentationStore.Publication? {
        defaults.synchronize()
        return store.read(at: date)
    }

    public func requestReadback() throws -> UUID {
        defaults.synchronize()
        return try store.requestReadback()
    }

    public func acknowledge(_ publication: RestCompanionPresentationStore.Publication) throws {
        defaults.synchronize()
        let bytes = try store.acknowledgement(for: publication)
        guard store.matchesCurrentPublication(bytes) else { throw AdapterError.stalePublication }
        defaults.set(bytes, forKey: Keys.acknowledgement)
        guard defaults.synchronize() else { throw AdapterError.persistenceRejected }
    }

    public func hasAcknowledgedCurrentPublication() -> Bool {
        defaults.synchronize()
        guard let bytes = defaults.object(forKey: Keys.acknowledgement) as? Data,
              bytes.count <= RestCompanionPresentationStore.maximumOccurrenceBytes else {
            return false
        }
        return store.matchesCurrentPublication(bytes)
    }

    /// Validate encoded bytes and metadata before requesting bounded, oriented pixels.
    public static func boundedImage(_ bytes: Data) -> CGImage? {
        guard (try? inspectImageHeader(bytes)) != nil,
              let source = CGImageSourceCreateWithData(bytes as CFData, [
                  kCGImageSourceShouldCache: false
              ] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: RestCompanionExport.maximumImageDimension,
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              image.width > 0, image.height > 0,
              image.width <= RestCompanionExport.maximumImageDimension,
              image.height <= RestCompanionExport.maximumImageDimension
        else { return nil }
        return image
    }

    /// Read properties only: no pixel decode occurs before encoded-size and dimension bounds.
    public static func inspectImageHeader(
        _ bytes: Data
    ) throws -> RestCompanionExport.ImageDimensions {
        guard bytes.count <= RestCompanionExport.maximumImageBytes else {
            throw RestCompanionExport.ValidationError.imageTooLarge
        }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
            let type = CGImageSourceGetType(source) as String?,
            [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier].contains(type),
            let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = metadata[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = metadata[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw RestCompanionExport.ValidationError.invalidImageHeader
        }
        let limit = Double(RestCompanionExport.maximumImageDimension)
        guard (1 ... limit).contains(width.doubleValue),
              (1 ... limit).contains(height.doubleValue),
              width.doubleValue.rounded() == width.doubleValue,
              height.doubleValue.rounded() == height.doubleValue else {
            throw RestCompanionExport.ValidationError.invalidImageDimensions
        }
        return .init(width: width.intValue, height: height.intValue)
    }

    private static func key(for slot: RestCompanionPresentationStore.Slot) -> String {
        switch slot {
        case .appearance: Keys.appearance
        case .occurrence: Keys.occurrence
        case .readbackRequest: Keys.readbackRequest
        }
    }
}
