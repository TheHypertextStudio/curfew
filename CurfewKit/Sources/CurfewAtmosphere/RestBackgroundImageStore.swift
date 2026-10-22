import CoreGraphics
import CurfewKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Owns optimized assets independently of the picker-selected originals.
public nonisolated struct RestBackgroundImageStore {
    public enum ImportError: Error {
        case invalidImage, unsupportedType, encodingFailed, outsideOwnedDirectory
    }

    private let directory: URL
    private static let maximumBytes = 2 * 1024 * 1024
    private static let maximumDimension = 3840

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func importImage(from url: URL) throws -> URL {
        guard url.isFileURL,
              let source = CGImageSourceCreateWithURL(
                  url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) as String?
        else { throw ImportError.invalidImage }
        guard [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier]
            .contains(type)
        else { throw ImportError.unsupportedType }

        // ImageIO downsamples directly; never allocate the original full-size bitmap.
        var rendition: Data?
        for dimension in [Self.maximumDimension, 2880, 1920, 1280] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options as CFDictionary
            ) else { throw ImportError.invalidImage }
            for quality in [0.9, 0.75, 0.55, 0.35, 0.15] {
                let bytes = NSMutableData()
                guard let output = CGImageDestinationCreateWithData(
                    bytes, UTType.jpeg.identifier as CFString, 1, nil
                ) else { throw ImportError.encodingFailed }
                // Only pixels and orientation-normalized dimensions survive import.
                CGImageDestinationAddImage(output, image, [
                    kCGImageDestinationLossyCompressionQuality: quality
                ] as CFDictionary)
                guard CGImageDestinationFinalize(output) else {
                    throw ImportError.encodingFailed
                }
                if bytes.length <= Self.maximumBytes {
                    rendition = bytes as Data
                    break
                }
            }
            if rendition != nil {
                break
            }
        }
        guard let rendition else { throw ImportError.encodingFailed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let owned = directory.appendingPathComponent(UUID().uuidString.lowercased() + ".jpg")
        try rendition.write(to: owned, options: .atomic)
        return owned
    }

    public func removeImage(at url: URL) throws {
        try validateOwnedURL(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Missing or damaged assets fall back to the built-in appearance in the host.
    /// Size and header bounds are checked before allocating decoded pixels.
    public func image(named filename: String?) -> CGImage? {
        guard let filename else { return nil }
        let url = directory.appendingPathComponent(filename)
        guard (try? validateOwnedURL(url)) != nil,
              let bytes = try? BoundedRegularFileReader.read(url, maximumBytes: Self.maximumBytes),
              !bytes.isEmpty,
              let source = CGImageSourceCreateWithData(
                  bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
              as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              (1 ... Self.maximumDimension).contains(width.intValue),
              (1 ... Self.maximumDimension).contains(height.intValue)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private func validateOwnedURL(_ url: URL) throws {
        let parent = url.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        guard url.isFileURL,
              parent.path == directory.path,
              UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
              ["jpg", "png", "heic"].contains(url.pathExtension.lowercased()),
              (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil
        else { throw ImportError.outsideOwnedDirectory }
    }
}
