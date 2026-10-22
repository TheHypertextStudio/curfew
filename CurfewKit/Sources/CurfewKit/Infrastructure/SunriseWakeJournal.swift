import Darwin
import Foundation

/// Durable helper-owned cancellation identity. The caller must serialize access
/// and supply a trusted parent directory owned by `requiredOwnerUserID`.
/// Daemon composition must use a root-owned parent, never user-writable state.
/// This journal has no native power operations and cannot cancel events.
public final class SunriseWakeJournal {
    public enum Failure: Error, Equatable {
        case unavailable
    }

    /// Contract scaffold only. No filesystem access or behavior is enabled.
    public init(url _: URL, owner _: String, requiredOwnerUserID _: uid_t) {}

    /// Intended contract: bounded (4096-byte), no-follow, single-link regular
    /// file read with descriptor ownership and fixed event-owner validation.
    public func load() throws -> SunriseWakeScheduler.Record? {
        throw Failure.unavailable
    }

    /// Intended contract: atomic durable private-file replacement. Nil clears
    /// only a validated owned journal. Malformed, foreign and unsafe entries
    /// must fail closed without replacement, deletion or native side effects.
    public func save(_: SunriseWakeScheduler.Record?) throws {
        throw Failure.unavailable
    }
}
