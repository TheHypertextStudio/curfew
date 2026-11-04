@testable import Curfew
import Darwin
import Foundation
import XCTest

@MainActor
final class AccountOAuthProcessLockTests: XCTestCase {
    func testSeparateAuthenticationSessionsAreSingleFlight() throws {
        let first = AccountOAuthAuthenticationGate()
        let second = AccountOAuthAuthenticationGate()
        try first.begin()
        defer { first.finish() }

        XCTAssertThrowsError(try second.begin()) { error in
            guard case AccountOAuthEnrollmentError.authenticationInProgress = error else {
                return XCTFail("Expected an active sign-in error")
            }
        }
    }

    func testAnotherProcessBlocksSignInAndCrashReleasesTheLock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lock = root.appendingPathComponent("oauth.lock")
        setenv("CURFEW_TEST_OAUTH_LOCK_PATH", lock.path, 1)
        defer { unsetenv("CURFEW_TEST_OAUTH_LOCK_PATH") }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-c", """
        import fcntl,os,sys
        fd=os.open(sys.argv[1],os.O_CREAT|os.O_RDWR,0o600)
        fcntl.flock(fd,fcntl.LOCK_EX)
        print('1',flush=True)
        sys.stdin.read()
        """, lock.path]
        let output = Pipe()
        let input = Pipe()
        child.standardOutput = output
        child.standardInput = input
        try child.run()
        defer {
            if child.isRunning {
                child.terminate()
            }
            child.waitUntilExit()
        }
        XCTAssertEqual(output.fileHandleForReading.readData(ofLength: 1), Data("1".utf8))
        let gate = AccountOAuthAuthenticationGate()
        XCTAssertThrowsError(try gate.begin())
        gate.finish()

        child.terminate()
        child.waitUntilExit()
        XCTAssertNoThrow(try gate.begin())
        gate.finish()
    }

    func testLockRefusesSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lock = root.appendingPathComponent("oauth.lock")
        try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: root)
        setenv("CURFEW_TEST_OAUTH_LOCK_PATH", lock.path, 1)
        defer { unsetenv("CURFEW_TEST_OAUTH_LOCK_PATH") }
        let gate = AccountOAuthAuthenticationGate()
        XCTAssertThrowsError(try gate.begin())
        gate.finish()
    }
}
