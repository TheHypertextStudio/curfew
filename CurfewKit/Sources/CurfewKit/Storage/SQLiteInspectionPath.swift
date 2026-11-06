import Darwin
import Foundation

/// SQLite NOFOLLOW rejects aliases in parent directories as well as at the leaf.
func sqliteInspectionPath(for databaseURL: URL) throws -> String {
    guard let parent = realpath(databaseURL.deletingLastPathComponent().path, nil) else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { free(parent) }
    // A URL reconstruction normalizes /private/var back to /var on macOS.
    return String(cString: parent) + "/" + databaseURL.lastPathComponent
}
