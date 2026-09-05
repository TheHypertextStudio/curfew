import Darwin
import Foundation

public enum BoundedRegularFileReadError: Error, Equatable {
    case unsafeEntry
    case tooLarge
    case readFailed(Int32)
}

/// Reads a user-controlled file without allowing filesystem object tricks to
/// block a privileged caller. The descriptor is nonblocking and no-follow,
/// the opened object must be a single-link regular file, and the byte limit is
/// enforced while reading rather than trusted from a racy `st_size` snapshot.
public enum BoundedRegularFileReader {
    public static func read(
        _ url: URL,
        maximumBytes: Int
    ) throws -> Data? {
        guard maximumBytes >= 0 else {
            throw BoundedRegularFileReadError.tooLarge
        }
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if errno == ENOENT {
                return nil
            }
            throw BoundedRegularFileReadError.unsafeEntry
        }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1
        else {
            throw BoundedRegularFileReadError.unsafeEntry
        }

        var result = Data()
        let chunkCapacity = 16384
        var buffer = [UInt8](repeating: 0, count: chunkCapacity)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count == 0 {
                return result
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw BoundedRegularFileReadError.readFailed(errno)
            }
            guard result.count <= maximumBytes - min(count, maximumBytes) else {
                throw BoundedRegularFileReadError.tooLarge
            }
            if result.count + count > maximumBytes {
                throw BoundedRegularFileReadError.tooLarge
            }
            result.append(buffer, count: count)
        }
    }
}
