import Darwin
import Foundation

public extension SunriseWakeJournal {
    /// Prepares the helper's private cancellation journal beneath a trusted base.
    /// Inert until actual filesystem contracts establish failing-first evidence.
    static func prepareDirectory(
        in trustedBase: URL,
        namespace: String,
        requiredOwnerUserID: uid_t
    ) throws -> URL {
        throw Failure.unavailable
    }
}
