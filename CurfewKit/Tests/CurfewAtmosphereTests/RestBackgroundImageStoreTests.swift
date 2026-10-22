import CoreGraphics
@testable import CurfewAtmosphere
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

struct RestBackgroundImageStoreTests {
    @Test(
        "Picker-selected JPEG, PNG and HEIC images become independent owned assets",
        arguments: [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier]
    )
    func ownsImportedImage(type: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.image(type: type, width: 64, height: 32)
        let store = RestBackgroundImageStore(directory: fixture.owned)
        let first = try store.importImage(from: source)
        let second = try store.importImage(from: source)
        #expect(first.deletingLastPathComponent().standardizedFileURL == fixture.owned
            .standardizedFileURL)
        #expect(UUID(uuidString: first.deletingPathExtension().lastPathComponent) != nil)
        #expect(first != second)
        try FileManager.default.removeItem(at: source)
        let decoded = try #require(CGImageSourceCreateWithURL(first as CFURL, nil))
        #expect(CGImageSourceCreateImageAtIndex(decoded, 0, nil) != nil)
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test("Large noisy imports are decodable within saver dimension and encoded-size limits")
    func boundsExportImage() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.image(
            type: UTType.png.identifier,
            width: 4000,
            height: 1000,
            noisy: true
        )
        #expect(try Data(contentsOf: source).count > 2 * 1024 * 1024)
        let result = try RestBackgroundImageStore(directory: fixture.owned)
            .importImage(from: source)
        let data = try Data(contentsOf: result)
        #expect(data.count <= 2 * 1024 * 1024)
        let decoded = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        #expect(max(image.width, image.height) <= 3840)
        #expect(image.width > 0 && image.height > 0)
        #expect(abs(Double(image.width) / Double(image.height) - 4) < 0.02)
    }

    @Test(
        "Corrupt images and unsupported encoded types leave no owned files",
        arguments: [false, true]
    )
    func rejectsInvalidImages(unsupported: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source: URL
        if unsupported {
            source = try fixture.image(type: UTType.tiff.identifier, width: 16, height: 16)
        } else {
            source = fixture.root.appendingPathComponent("broken.png")
            try Data("not an image".utf8).write(to: source)
        }
        let store = RestBackgroundImageStore(directory: fixture.owned)
        #expect(throws: (any Error).self) { try store.importImage(from: source) }
        let exists = FileManager.default.fileExists(atPath: fixture.owned.path)
        if exists {
            #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.owned.path).isEmpty)
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Removing an owned asset is idempotent and preserves its original")
    func removesOwnedImage() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.image(type: UTType.png.identifier, width: 16, height: 16)
        let store = RestBackgroundImageStore(directory: fixture.owned)
        let owned = try store.importImage(from: source)
        try store.removeImage(at: owned)
        try store.removeImage(at: owned)
        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Removal cannot delete the picker-selected original outside owned storage")
    func refusesRemovalOutsideOwnedDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.image(type: UTType.png.identifier, width: 16, height: 16)
        let store = RestBackgroundImageStore(directory: fixture.owned)
        #expect(throws: (any Error).self) { try store.removeImage(at: source) }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    private struct Fixture {
        let root: URL
        var owned: URL {
            root.appendingPathComponent("owned", isDirectory: true)
        }

        init() throws {
            self.root = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }

        func image(type: String, width: Int, height: Int, noisy: Bool = false) throws -> URL {
            var state: UInt32 = 42
            var pixels = [UInt8](repeating: 127, count: width * height * 4)
            if noisy {
                for index in pixels.indices {
                    state = state &* 1_664_525 &+ 1_013_904_223
                    pixels[index] = UInt8(truncatingIfNeeded: state >> 24)
                }
            }
            for index in stride(from: 3, to: pixels.count, by: 4) {
                pixels[index] = 255
            }
            let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
            let image = try #require(CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ))
            let url = root.appendingPathComponent(UUID().uuidString)
            let destination = try #require(CGImageDestinationCreateWithURL(
                url as CFURL,
                type as CFString,
                1,
                nil
            ))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
            return url
        }
    }
}
