import Darwin
import Foundation

/// Publishes complete private files without exposing bytes under a public mode.
/// Exclusive publication lets concurrent first signers keep the same key.
enum BreakGlassPrivateFileWriter {
    @discardableResult
    static func write(_ data: Data, to url: URL, replaceExisting: Bool) throws -> Bool {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let directory = open(
            url.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard directory >= 0 else { throw posixError() }
        defer { close(directory) }
        let temporary = ".break-glass-\(UUID().uuidString).tmp"
        let descriptor = openat(
            directory,
            temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else { throw posixError() }
        defer {
            close(descriptor)
            unlinkat(directory, temporary, 0)
        }
        guard fchmod(descriptor, 0o600) == 0 else { throw posixError() }
        try write(data, to: descriptor)
        guard fsync(descriptor) == 0 else { throw posixError() }
        let flags: UInt32 = replaceExisting ? 0 : UInt32(RENAME_EXCL)
        guard renameatx_np(directory, temporary, directory, url.lastPathComponent, flags) == 0
        else {
            if !replaceExisting, errno == EEXIST {
                return false
            }
            throw posixError()
        }
        guard fsync(directory) == 0 else { throw posixError() }
        return true
    }

    private static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    bytes.count - offset
                )
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
