import Foundation
import MachO

enum CLIExecutable {
    static func location() throws -> URL {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { throw CocoaError(.fileReadUnknown) }
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
    }
}
