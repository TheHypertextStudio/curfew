import CryptoKit
@testable import Curfew
import Foundation
import Testing

/// The shader ships precompiled so no build needs the Metal toolchain. These
/// checks need no compiler: the checked-in library must match its source, and
/// the bundled copy must load and expose the Horizon function.
struct HorizonShaderLibraryTests {
    private static let horizon = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Horizon/
        .deletingLastPathComponent() // UI/
        .deletingLastPathComponent() // CurfewTests/
        .deletingLastPathComponent() // <repo>/
        .appendingPathComponent("Curfew/UI/Horizon", isDirectory: true)

    @Test("The checked-in library was compiled from the current shader source")
    func libraryMatchesSource() throws {
        let source = try Data(contentsOf: Self.horizon.appendingPathComponent("HorizonSky.metal"))
        let digest = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
        let recorded = try String(
            contentsOf: Self.horizon.appendingPathComponent("HorizonSky.metal.sha256"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(
            recorded == digest,
            "HorizonSky.metal changed; regenerate it with scripts/build-horizon-shader.sh"
        )
    }

    @Test("The bundled library loads and exposes the Horizon function")
    func bundledLibraryLoads() throws {
        let library = try #require(HorizonShaderLibrary.shared)
        #expect(HorizonShaderLibrary.functionNames(at: library.url).contains("horizonSky"))
    }

    @Test("A bundle without the library yields nothing, so the sky falls back to the CPU image")
    func missingLibraryFallsBack() {
        #expect(HorizonShaderLibrary.load(from: Bundle(for: NSObject.self)) == nil)
    }
}
