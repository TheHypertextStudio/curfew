@testable import CurfewKit
import Foundation
import Testing

struct SupervisorBundleLocationTests {
    @Test("A bundled supervisor resolves its enclosing application")
    func resolvesEnclosingApplication() {
        let executable =
            URL(fileURLWithPath: "/Applications/Curfew.app/Contents/Resources/curfew-supervisor")
        #expect(SupervisorBundleLocation.enclosingApplication(executableURL: executable)
            == URL(fileURLWithPath: "/Applications/Curfew.app", isDirectory: true))
    }

    @Test("A relative service argument cannot identify the application")
    func rejectsRelativeServiceArgument() throws {
        let relativeArgument = "Contents/Resources/curfew-supervisor"
        let argumentURL = URL(fileURLWithPath: relativeArgument)
        #expect(SupervisorBundleLocation.enclosingApplication(executableURL: argumentURL) == nil)
        let actual = try #require(SupervisorBundleLocation.executableURL())
        #expect(actual.path.hasPrefix("/"))
        #expect(FileManager.default.isExecutableFile(atPath: actual.path))
        #expect(actual.path != argumentURL.path)
    }

    @Test("An executable outside the bundled Resources directory is rejected")
    func rejectsOutsideBundle() {
        for path in [
            "/usr/local/bin/curfew-supervisor",
            "/Applications/Curfew.app/Contents/MacOS/curfew-supervisor",
            "/Applications/Curfew.app/Resources/curfew-supervisor"
        ] {
            #expect(SupervisorBundleLocation.enclosingApplication(
                executableURL: URL(fileURLWithPath: path)
            ) == nil)
        }
    }

    @Test("An oversized loader path request is rejected before allocation or retry")
    func boundsLoaderPathSize() {
        var reads = 0
        let resolved = SupervisorBundleLocation.executableURL { _, size in
            reads += 1
            size.pointee = UInt32.max
            return -1
        }
        #expect(resolved == nil)
        #expect(reads == 1)
    }

    @Test("The loader path resolves independently of argv and the process working directory")
    func usesLoaderPath() throws {
        let path = "/Applications/Curfew (Dev).app/Contents/Resources/curfew-supervisor"
        var reads = 0
        let resolved = SupervisorBundleLocation.executableURL { buffer, size in
            reads += 1
            let bytes = Array(path.utf8CString)
            if size.pointee < UInt32(bytes.count) {
                size.pointee = UInt32(bytes.count)
                return -1
            }
            for (index, byte) in bytes.enumerated() {
                buffer[index] = byte
            }
            return 0
        }
        #expect(reads == 2)
        #expect(resolved == URL(fileURLWithPath: path))
        let actual = try #require(resolved)
        #expect(SupervisorBundleLocation.enclosingApplication(executableURL: actual)
            == URL(fileURLWithPath: "/Applications/Curfew (Dev).app", isDirectory: true))
    }
}
