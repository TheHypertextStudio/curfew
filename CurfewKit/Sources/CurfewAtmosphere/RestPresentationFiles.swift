import CurfewKit
import Darwin
import Foundation

/// Presentation-only exchange outside the host's redirected preference container.
/// Each slot is independently bounded, private, and atomically replaced. The host
/// only reads these files and persists its configuration through ScreenSaverDefaults.
final class RestPresentationFiles {
    enum Failure: Error { case unavailable, oversized }
    let directory: URL
    private let lock = NSLock()
    private var cache: [RestCompanionPresentationStore.Slot: (String, Data)] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    func remove(_ slot: RestCompanionPresentationStore.Slot) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let directoryFD = try openDirectory(create: false) else { return }
        defer { close(directoryFD) }
        let name = filename(slot)
        var metadata = stat()
        guard fstatat(directoryFD, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT {
                return
            }
            throw Failure.unavailable
        }
        try validateFile(metadata)
        guard unlinkat(directoryFD, name, 0) == 0, fsync(directoryFD) == 0 else {
            throw Failure.unavailable
        }
        cache[slot] = nil
    }

    static func systemDirectory() throws -> URL {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { throw Failure.unavailable }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent(
                "Library/Application Support/studio.hypertext.apps.curfew.screensaver"
            )
    }

    func write(_ slot: RestCompanionPresentationStore.Slot, bytes: Data) throws {
        guard bytes.count <= limit(slot) else { throw Failure.oversized }
        lock.lock()
        defer { lock.unlock() }
        guard let directoryFD = try openDirectory(create: true) else { throw Failure.unavailable }
        defer { close(directoryFD) }
        let name = filename(slot)
        var existing = stat()
        if fstatat(directoryFD, name, &existing, AT_SYMLINK_NOFOLLOW) == 0 {
            try validateFile(existing)
        } else if errno != ENOENT {
            throw Failure.unavailable
        }
        let temporary = ".\(UUID().uuidString).tmp"
        let file = openat(
            directoryFD,
            temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard file >= 0 else { throw Failure.unavailable }
        defer {
            close(file)
            unlinkat(directoryFD, temporary, 0)
        }
        try writeBytes(bytes, to: file)
        guard fsync(file) == 0, renameat(directoryFD, temporary, directoryFD, name) == 0,
              fsync(directoryFD) == 0 else { throw Failure.unavailable }
        cache[slot] = nil
    }

    func read(_ slot: RestCompanionPresentationStore.Slot, maximum: Int) throws -> Data? {
        guard maximum >= 0 else { throw Failure.oversized }
        lock.lock()
        defer { lock.unlock() }
        guard let directoryFD = try openDirectory(create: false) else { return nil }
        defer { close(directoryFD) }
        let file = openat(
            directoryFD,
            filename(slot),
            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        )
        guard file >= 0 else {
            if errno == ENOENT {
                return nil
            }
            throw Failure.unavailable
        }
        defer { close(file) }
        var metadata = stat()
        guard fstat(file, &metadata) == 0 else { throw Failure.unavailable }
        try validateFile(metadata)
        let bound = min(maximum, limit(slot))
        guard metadata.st_size >= 0, metadata.st_size <= bound else { throw Failure.oversized }
        let stamp = "\(metadata.st_dev):\(metadata.st_ino):\(metadata.st_size):"
            + "\(metadata.st_mtimespec.tv_sec):\(metadata.st_mtimespec.tv_nsec)"
        if let cached = cache[slot], cached.0 == stamp {
            return cached.1
        }
        let bytes = try readBytes(file, maximum: bound)
        cache[slot] = (stamp, bytes)
        return bytes
    }

    private func openDirectory(create: Bool) throws -> Int32? {
        guard directory.isFileURL,
              directory.standardizedFileURL.path == directory.resolvingSymlinksInPath().path
        else { throw Failure.unavailable }
        if create, mkdir(directory.path, 0o700) != 0, errno != EEXIST {
            throw Failure.unavailable
        }
        let descriptor = open(
            directory.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if !create, errno == ENOENT {
                return nil
            }
            throw Failure.unavailable
        }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_uid == geteuid(), metadata.st_mode & 0o7777 == 0o700 else {
            close(descriptor)
            throw Failure.unavailable
        }
        return descriptor
    }

    private func validateFile(_ metadata: stat) throws {
        guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_uid == geteuid(),
              metadata.st_nlink == 1, metadata.st_mode & 0o7777 == 0o600
        else { throw Failure.unavailable }
    }

    private func filename(_ slot: RestCompanionPresentationStore.Slot) -> String {
        switch slot {
        case .appearance: "appearance.v1.json"
        case .occurrence: "occurrence.v1.json"
        case .readbackRequest: "request.v1.json"
        }
    }

    private func limit(_ slot: RestCompanionPresentationStore.Slot) -> Int {
        slot == .appearance ? RestCompanionPresentationStore.maximumAppearanceBytes
            : RestCompanionPresentationStore.maximumOccurrenceBytes
    }

    private func writeBytes(_ bytes: Data, to descriptor: Int32) throws {
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(
                    descriptor,
                    buffer.baseAddress!.advanced(by: offset),
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

    private func readBytes(_ descriptor: Int32, maximum: Int) throws -> Data {
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR {
                continue
            }
            guard count >= 0 else { throw Failure.unavailable }
            if count == 0 {
                return bytes
            }
            guard count <= maximum - bytes.count else { throw Failure.oversized }
            bytes.append(buffer, count: count)
        }
    }
}
