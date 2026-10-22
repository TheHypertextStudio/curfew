import Foundation

/// Unconsumed TDD scaffold; import behavior follows actual failing-first evidence.
nonisolated struct RestBackgroundImageStore {
    enum ImportError: Error {
        case unavailable
    }

    init(directory: URL) {}

    func importImage(from url: URL) throws -> URL {
        throw ImportError.unavailable
    }

    func removeImage(at url: URL) throws {
        throw ImportError.unavailable
    }
}
