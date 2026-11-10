import Darwin
import Foundation

/// Durable helper-owned cancellation identity. The caller must serialize access
/// and supply a trusted parent path whose ancestors cannot be redirected.
/// Daemon composition must use a root-owned parent, never user-writable state.
/// This journal has no native power operations and cannot cancel events.
public final class SunriseWakeJournal {
    public enum Failure: Error, Equatable {
        case unavailable
    }

    private let url: URL
    private let owner: String
    private let requiredOwnerUserID: uid_t
    private let maximumBytes = 4096

    public init(url: URL, owner: String, requiredOwnerUserID: uid_t) {
        self.url = url
        self.owner = owner
        self.requiredOwnerUserID = requiredOwnerUserID
    }

    public func load() throws -> SunriseWakeScheduler.Record? {
        let directory = try openParent()
        defer { close(directory) }
        return try readRecord(in: directory)
    }

    /// Failure after rename/unlink can mean publication succeeded but directory
    /// durability could not be confirmed. Callers must reload before recovery.
    public func save(_ record: SunriseWakeScheduler.Record?) throws {
        let bytes = try encodedRecord(record)
        let directory = try openParent()
        defer { close(directory) }
        let existing = try readRecord(in: directory)
        if let bytes {
            try publish(bytes, in: directory)
        } else if existing != nil {
            try clearOwnedRecord(in: directory)
        }
    }

    private func encodedRecord(_ record: SunriseWakeScheduler.Record?) throws -> Data? {
        // Reject unauthorized input before opening or modifying existing state.
        guard let record else { return nil }
        try validate(record)
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count <= maximumBytes else { throw Failure.unavailable }
        return bytes
    }

    private func clearOwnedRecord(in directory: Int32) throws {
        guard unlinkat(directory, url.lastPathComponent, 0) == 0,
              fsync(directory) == 0 else { throw Failure.unavailable }
    }

    private func publish(_ bytes: Data, in directory: Int32) throws {
        let temporaryName = ".sunrise-\(UUID().uuidString).tmp"
        let descriptor = openat(
            directory, temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw Failure.unavailable }
        var published = false
        defer {
            close(descriptor)
            if !published {
                _ = unlinkat(directory, temporaryName, 0)
            }
        }
        try validateTemporaryFile(descriptor)
        try writeAll(bytes, to: descriptor)
        guard fsync(descriptor) == 0, renameat(
            directory,
            temporaryName,
            directory,
            url.lastPathComponent
        ) == 0 else {
            throw Failure.unavailable
        }
        published = true
        guard fsync(directory) == 0 else { throw Failure.unavailable }
    }

    private func validateTemporaryFile(_ descriptor: Int32) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_uid == requiredOwnerUserID,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1,
              fchmod(descriptor, mode_t(0o600)) == 0
        else { throw Failure.unavailable }
    }

    private func writeAll(_ bytes: Data, to descriptor: Int32) throws {
        try bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { throw Failure.unavailable }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    buffer.count - offset
                )
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else { throw Failure.unavailable }
                offset += count
            }
        }
    }

    private func openParent() throws -> Int32 {
        let name = url.lastPathComponent
        guard url.isFileURL, !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !url.path.contains("\0")
        else { throw Failure.unavailable }
        let descriptor = open(
            url.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard descriptor >= 0 else { throw Failure.unavailable }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_uid == requiredOwnerUserID,
              metadata.st_mode & 0o022 == 0
        else {
            close(descriptor)
            throw Failure.unavailable
        }
        return descriptor
    }

    private func readRecord(in directory: Int32) throws -> SunriseWakeScheduler.Record? {
        let descriptor = openat(
            directory, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if errno == ENOENT {
                return nil
            }
            throw Failure.unavailable
        }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_uid == requiredOwnerUserID,
              metadata.st_nlink == 1,
              metadata.st_size >= 0, metadata.st_size <= off_t(maximumBytes)
        else { throw Failure.unavailable }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: maximumBytes + 1)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count < 0, errno == EINTR {
                continue
            }
            guard count >= 0 else { throw Failure.unavailable }
            if count == 0 {
                break
            }
            guard bytes.count + count <= maximumBytes else { throw Failure.unavailable }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        let record = try JSONDecoder().decode(SunriseWakeScheduler.Record.self, from: bytes)
        try validate(record)
        return record
    }

    private func validate(_ record: SunriseWakeScheduler.Record) throws {
        guard record.plan.owner == owner,
              record.plan.wakeAt.timeIntervalSince1970.isFinite,
              record.plan.holdUntil.timeIntervalSince1970.isFinite,
              record.plan.holdUntil > record.plan.wakeAt
        else { throw Failure.unavailable }
    }
}
