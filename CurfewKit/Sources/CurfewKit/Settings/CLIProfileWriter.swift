import Darwin
import Foundation

enum CLIProfileWriter {
    private static let fileManager = FileManager.default

    static func write(_ data: Data, to url: URL, replacing expected: Data) throws {
        try validateSnapshot(expected, at: url)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let staging = url.deletingLastPathComponent()
            .appendingPathComponent(".curfew-profile-\(UUID().uuidString)")
        let descriptor = open(
            staging.path,
            O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else { throw Self.posixError() }
        defer { close(descriptor); unlink(staging.path) }
        try writeAll(data, to: descriptor)
        let original = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if original < 0, errno != ENOENT {
            throw Self.posixError()
        }
        defer {
            if original >= 0 {
                close(original)
            }
        }
        if original >= 0 {
            var metadata = stat()
            guard fstat(original, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1,
                  metadata.st_uid == geteuid() else {
                throw CLIInstallationError(
                    "The shell profile must be a regular file owned by your account."
                )
            }
            guard fcopyfile(original, descriptor, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0
            else {
                throw Self.posixError()
            }
        }
        guard fsync(descriptor) == 0 else { throw Self.posixError() }
        try validateSnapshot(expected, at: url)
        try validateIdentity(original, at: url)
        guard
            rename(staging.path, url.path) == 0 else { throw Self.posixError() }
    }

    private static func validateSnapshot(_ expected: Data, at url: URL) throws {
        let current = try BoundedRegularFileReader.read(url, maximumBytes: 1024 * 1024) ?? Data()
        guard current == expected else {
            throw CLIInstallationError(
                "The shell profile changed during setup. Your edits were preserved."
            )
        }
    }

    private static func validateIdentity(_ descriptor: Int32, at url: URL) throws {
        var latest = stat()
        let exists = lstat(url.path, &latest) == 0
        if !exists, errno != ENOENT {
            throw Self.posixError()
        }
        var original = stat()
        if descriptor >= 0, exists, fstat(descriptor, &original) == 0,
           latest.st_dev == original.st_dev, latest.st_ino == original.st_ino {
            return
        }
        if descriptor < 0, !exists {
            return
        }
        throw CLIInstallationError(
            "The shell profile changed during setup. Your edits were preserved."
        )
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let count = Darwin.write(
                    descriptor,
                    buffer.baseAddress!.advanced(by: written),
                    buffer.count - written
                )
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else { throw Self.posixError() }
                written += count
            }
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
