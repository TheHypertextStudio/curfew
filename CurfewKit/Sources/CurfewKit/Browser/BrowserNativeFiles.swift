import Darwin
import Foundation

/// Private files are created with their final mode before the atomic rename.
/// Tightening permissions after Data.write would expose review text briefly.
public nonisolated enum BrowserNativeFiles {
    public static func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFDIR, metadata.st_uid == geteuid()
        else { throw BrowserNativeError.unsafeFile }
        guard chmod(url.path, 0o700) == 0 else { throw BrowserNativeError.unsafeFile }
    }

    public static func write(_ data: Data, to url: URL) throws {
        try prepareDirectory(url.deletingLastPathComponent())
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        let descriptor = open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else { throw BrowserNativeError.unsafeFile }
        defer {
            close(descriptor)
            unlink(temporary.path)
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset
                )
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else { throw BrowserNativeError.unsafeFile }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, rename(temporary.path, url.path) == 0 else {
            throw BrowserNativeError.unsafeFile
        }
    }

    public static func read(_ url: URL, maximumBytes: Int = 4 * 1024 * 1024) throws -> Data? {
        var metadata = stat()
        if lstat(url.path, &metadata) != 0 {
            if errno == ENOENT {
                return nil
            }
            throw BrowserNativeError.unsafeFile
        }
        guard metadata.st_uid == geteuid(), metadata.st_mode & 0o077 == 0 else {
            throw BrowserNativeError.unsafeFile
        }
        return try BoundedRegularFileReader.read(url, maximumBytes: maximumBytes)
    }

    static func locked<T>(
        directory: URL,
        createDirectory: Bool = true,
        operation: () throws -> T
    ) throws -> T {
        if createDirectory {
            try prepareDirectory(directory)
        }
        let descriptor = open(
            directory.appendingPathComponent(".lock").path,
            O_RDWR | O_NOFOLLOW | O_CLOEXEC | (createDirectory ? O_CREAT : 0),
            0o600
        )
        guard descriptor >= 0 else { throw BrowserNativeError.unsafeFile }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_uid == geteuid(),
              metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1,
              fchmod(descriptor, 0o600) == 0, flock(descriptor, LOCK_EX) == 0
        else { throw BrowserNativeError.unsafeFile }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
