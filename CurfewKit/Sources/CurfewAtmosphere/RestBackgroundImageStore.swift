import Foundation

/// Unconsumed TDD scaffold; import behavior follows actual failing-first evidence.
public nonisolated struct RestBackgroundImageStore {
    enum ImportError: Error {
        case unavailable
    }

    public init(directory: URL) {}

    public func importImage(from url: URL) throws -> URL {
        throw ImportError.unavailable
    }

    public func removeImage(at url: URL) throws {
        throw ImportError.unavailable
    }
}
