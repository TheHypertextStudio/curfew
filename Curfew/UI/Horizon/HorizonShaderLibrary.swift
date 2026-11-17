import Foundation
import Metal
import SwiftUI

/// The compiled Horizon shader, checked in as `HorizonSky.metallib` and bundled
/// as a resource so no build needs the Metal toolchain. Regenerate it from
/// `HorizonSky.metal` with `scripts/build-horizon-shader.sh`.
///
/// The library is looked up in the bundle that holds this code: the app, or the
/// screen saver loaded into the system's saver host, whose main bundle is not
/// ours. It is validated once with Metal so a missing or unreadable library
/// falls back to the CPU still image instead of drawing nothing.
///
/// This file is compiled into both the app and the screen saver bundle.
struct HorizonShaderLibrary: Sendable {
    static let resourceName = "HorizonSky"
    static let functionName = "horizonSky"

    let url: URL
    let library: ShaderLibrary

    /// The loaded library, or nil when it is missing or does not contain
    /// the Horizon function.
    static let shared: HorizonShaderLibrary? = load(from: Bundle(for: HorizonBundleToken.self))

    static func load(from bundle: Bundle) -> HorizonShaderLibrary? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "metallib"),
              functionNames(at: url).contains(functionName) else { return nil }
        return HorizonShaderLibrary(url: url, library: ShaderLibrary(url: url))
    }

    /// The function names a compiled library exposes, read with Metal (no
    /// compiler needed). Empty when the library cannot load.
    static func functionNames(at url: URL) -> [String] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeLibrary(URL: url) else { return [] }
        return library.functionNames
    }
}

private final class HorizonBundleToken {}
