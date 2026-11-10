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
    private let fallbackStore: RestCompanionPresentationStore
    private let cachedPreferences: RestScreenSaverPreferences?
    private let postReceipt: (Data) -> Void
    private let fullScreenHost: Bool
    private var fullScreenReceipt: Data?
    private var receiptObserver: NSObjectProtocol?
    private static let receiptName = Notification
        .Name(moduleIdentifier + ".presentation-readback.v1")

    public convenience init(
        defaults: UserDefaults,
        inspectImageHeader: @escaping (Data) throws -> RestCompanionExport.ImageDimensions =
            RestScreenSaverPreferences.inspectImageHeader
    ) {
        self.init(
            defaults: defaults,
            files: nil,
            host: false,
            inspectImageHeader: inspectImageHeader
        )
    }

    init(
        defaults: UserDefaults, files: RestPresentationFiles?, host: Bool,
        postReceipt: @escaping (Data) -> Void = { _ in },
        fullScreenHost: Bool = false,
        inspectImageHeader: @escaping (Data) throws -> RestCompanionExport.ImageDimensions =
            RestScreenSaverPreferences.inspectImageHeader
    ) {
        self.defaults = defaults
        self.postReceipt = postReceipt
        self.fullScreenHost = fullScreenHost
        self.cachedPreferences = host ? RestScreenSaverPreferences(defaults: defaults) : nil
        self.fallbackStore = RestCompanionPresentationStore(
            read: { slot, maximum in
                guard slot == .appearance,
                      let bytes = defaults.object(forKey: Self.Keys.appearance) as? Data,
                      bytes.count <= maximum else { return nil }
                return bytes
            },
            write: { _, _ in throw AdapterError.unavailable },
            inspectImageHeader: inspectImageHeader
        )
        self.store = RestCompanionPresentationStore(
            read: { slot, maximum in
                if host, let files {
                    return try files.read(slot, maximum: maximum)
                }
                guard let bytes = defaults.object(forKey: Self.key(for: slot)) as? Data,
                      bytes.count <= maximum else { return nil }
                return bytes
            },
            write: { slot, bytes in
                if !host {
                    try files?.write(slot, bytes: bytes)
                }
                defaults.set(bytes, forKey: Self.key(for: slot))
                guard defaults.synchronize() else { throw AdapterError.persistenceRejected }
            },
            inspectImageHeader: inspectImageHeader
        )
    }

    deinit {
        if let receiptObserver {
            DistributedNotificationCenter.default().removeObserver(receiptObserver)
        }
    }

    /// The app publishes only validated presentation slots, not its preference container.
    public static func system() throws -> RestScreenSaverPreferences {
        let preferences = try nativePreferences(host: false)
        preferences.receiptObserver = DistributedNotificationCenter.default().addObserver(
            forName: receiptName, object: nil, queue: .main
        ) { [weak preferences] notification in
            guard let value = notification.object as? String, value.utf8.count <= 8192,
                  let bytes = Data(base64Encoded: value) else { return }
            preferences?.acceptHostAcknowledgement(bytes)
        }
        return preferences
    }

    /// The actual sandboxed host keeps its own ScreenSaverDefaults configuration.
    public static func companionSystem(isPreview: Bool = true) throws
        -> RestScreenSaverPreferences {
        try nativePreferences(host: true, fullScreenHost: !isPreview)
    }

    private static func nativePreferences(
        host: Bool,
        fullScreenHost: Bool = false
    ) throws -> RestScreenSaverPreferences {
        guard let defaults = ScreenSaverDefaults(forModuleWithName: moduleIdentifier) else {
            throw AdapterError.unavailable
        }
        return try RestScreenSaverPreferences(
            defaults: defaults,
            files: RestPresentationFiles(directory: RestPresentationFiles.systemDirectory()),
            host: host,
            postReceipt: { bytes in
                DistributedNotificationCenter.default().postNotificationName(
                    receiptName, object: bytes.base64EncodedString(), userInfo: nil,
                    deliverImmediately: true
                )
            },
            fullScreenHost: fullScreenHost
        )
    }

    @discardableResult
    func acceptHostAcknowledgement(_ bytes: Data) -> Bool {
        guard bytes.count <= RestCompanionPresentationStore.maximumOccurrenceBytes,
              store.matchesCurrentPublication(bytes) else { return false }
        if let record = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           record["fullScreen"] as? Bool == true {
            fullScreenReceipt = bytes
        }
        defaults.set(bytes, forKey: Keys.acknowledgement)
        return defaults.synchronize()
    }

    public func publish(snapshot: RestSceneSnapshot, imageData: Data?) throws {
        defaults.synchronize()
        try store.publish(snapshot: snapshot, imageData: imageData)
    }

    public func read(at date: Date) -> RestCompanionPresentationStore.Publication? {
        defaults.synchronize()
        let publication = store.read(at: date)
            ?? (cachedPreferences == nil ? nil : fallbackStore.read(at: date))
        if let publication, let cachedPreferences {
            // Persist only the decoded allowlist. Never copy unvalidated file bytes
            // into the host's module preferences or copy application-private data.
            try? cachedPreferences.store.cacheAppearance(from: publication)
        }
        return publication
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
        var receipt = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] ?? [:]
        receipt["fullScreen"] = fullScreenHost
        try postReceipt(JSONSerialization.data(withJSONObject: receipt))
    }

    public func hasFullScreenAcknowledgement() -> Bool {
        guard let fullScreenReceipt else { return false }
        return store.matchesCurrentPublication(fullScreenReceipt)
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
