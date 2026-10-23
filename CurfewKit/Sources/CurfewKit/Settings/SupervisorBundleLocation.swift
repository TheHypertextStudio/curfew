import Foundation
import MachO

/// SMAppService supplies relative argv, so the supervisor locates its bundle through dyld.
public nonisolated enum SupervisorBundleLocation {
    public static func executableURL() -> URL? {
        executableURL { _NSGetExecutablePath($0, $1) }
    }

    static func executableURL(
        readPath: (UnsafeMutablePointer<CChar>, UnsafeMutablePointer<UInt32>) -> Int32
    ) -> URL? {
        var probe: CChar = 0
        var size: UInt32 = 1
        // Reject impossible loader results instead of allocating an unbounded buffer.
        guard readPath(&probe, &size) == -1, size > 1, size <= 64 * 1024 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard readPath(&buffer, &size) == 0,
              let terminator = buffer.firstIndex(of: 0), terminator > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { bytes in
            guard let path = bytes.baseAddress else { return nil }
            return URL(
                fileURLWithFileSystemRepresentation: path,
                isDirectory: false,
                relativeTo: nil
            )
            .resolvingSymlinksInPath()
        }
    }

    public static func enclosingApplication(executableURL: URL) -> URL? {
        guard executableURL.isFileURL else { return nil }
        let resources = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()
        let contents = resources.deletingLastPathComponent()
        let application = contents.deletingLastPathComponent()
        guard resources.lastPathComponent == "Resources",
              contents.lastPathComponent == "Contents",
              application.pathExtension == "app" else { return nil }
        return application
    }
}
