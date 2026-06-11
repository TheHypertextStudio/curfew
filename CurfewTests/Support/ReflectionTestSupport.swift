@testable import Curfew
import Foundation

/// Test-only helpers for building throwaway ``ReflectionStore`` instances,
/// mirroring ``ActivityTestSupport``. Each call gets its own hermetic database
/// in a fresh temp directory so the suite is parallel-safe.
enum ReflectionTestSupport {
    /// Creates a ``ReflectionStore`` in a fresh temp directory keyed off
    /// `label` for easier debugging of leftover artefacts.
    static func makeEphemeralStore(label: String) throws -> ReflectionStore {
        let base = FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent(
            "curfew-reflection-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return try ReflectionStore(directory: directory)
    }
}
