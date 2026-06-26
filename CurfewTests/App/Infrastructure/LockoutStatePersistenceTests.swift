@testable import Curfew
import CurfewKit
import Foundation
import Testing

struct LockoutStatePersistenceTests {
    @Test("markLockoutActive creates the sentinel when its directory exists")
    func markLockoutActiveCreatesSentinel() throws {
        let directory = try ephemeralDirectory(label: "active")
        let sentinelURL = directory.appendingPathComponent("lockout-active")
        let persistence = LockoutStatePersistence(
            fileManager: .default,
            sentinelURL: sentinelURL
        )

        persistence.markLockoutActive()

        #expect(FileManager.default.fileExists(atPath: sentinelURL.path))
    }

    @Test("markLockoutInactive removes the sentinel when present")
    func markLockoutInactiveRemovesSentinel() throws {
        let directory = try ephemeralDirectory(label: "inactive")
        let sentinelURL = directory.appendingPathComponent("lockout-active")
        try Data().write(to: sentinelURL)
        let persistence = LockoutStatePersistence(
            fileManager: .default,
            sentinelURL: sentinelURL
        )

        persistence.markLockoutInactive()

        #expect(!FileManager.default.fileExists(atPath: sentinelURL.path))
    }

    @Test("markLockoutActive no-ops when the parent directory is missing")
    func markLockoutActiveNoopsWithoutParentDirectory() throws {
        let directory = try ephemeralDirectory(label: "missing-parent")
        let sentinelURL = directory
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("lockout-active")
        let persistence = LockoutStatePersistence(
            fileManager: .default,
            sentinelURL: sentinelURL
        )

        persistence.markLockoutActive()

        #expect(!FileManager.default.fileExists(atPath: sentinelURL.path))
    }

    private func ephemeralDirectory(label: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "curfew-lockout-state-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
