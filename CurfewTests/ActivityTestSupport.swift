@testable import Curfew
import Foundation

/// Test-only helpers for building throwaway ``ActivityStore`` instances.
///
/// Every test that exercises activity logging needs its own hermetic
/// database — sharing one would let events leak between tests. The helper
/// below creates a fresh temp directory per call and opens a store rooted
/// inside it. The directory is left on disk intentionally: macOS cleans
/// `/var/folders/.../TemporaryItems` periodically, and emitting cleanup
/// from every test would just make failures noisier without measurable
/// benefit on typical developer machines.
enum ActivityTestSupport {
    /// Creates an ``ActivityStore`` in a fresh temp directory keyed off
    /// `label`, which appears in the directory name to aid debugging
    /// when you `ls /var/folders` to inspect leftover artefacts.
    static func makeEphemeralStore(label: String) throws -> ActivityStore {
        let base = FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent(
            "curfew-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return try ActivityStore(directory: directory)
    }
}
