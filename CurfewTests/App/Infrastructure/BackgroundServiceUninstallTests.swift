@testable import Curfew
import CurfewKit
import Foundation
import ServiceManagement
import Testing

@MainActor
struct BackgroundServiceUninstallTests {
    @Test func failedUnregisterPreservesBrowserAndLocalState() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = BrowserNativeInstallation.browserDirectory(home: home, flavor: .current)
        let browser = BrowserNativeStore(directory: directory)
        try browser.activate()
        let state = directory.deletingLastPathComponent()
            .appendingPathComponent("enforcement-runtime.json")
        let contents = Data("spent budget".utf8)
        try contents.write(to: state)
        let service = UninstallBackgroundServiceStub()
        service.failsUnregister = true
        let manager = BackgroundServiceManager(service: service, retireLegacyGuard: {})

        var stopped = false
        let outcome = UninstallCoordinator.performUninstall(
            home: home,
            defaultsSuiteName: "studio.hypertext.curfew.tests.\(UUID().uuidString)",
            unregisterServices: { [] },
            eraseKeychainService: { _ in },
            backgroundService: manager,
            onRecoveryStopped: { stopped = true }
        )

        #expect(service.unregisterCount == 1)
        #expect(!outcome.allSucceeded)
        #expect(!stopped)
        #expect(outcome.removed.isEmpty)
        #expect(outcome.failed.map(\.path) == ["Background recovery service"])
        #expect(try browser.isActive())
        #expect(try Data(contentsOf: state) == contents)
    }

    @Test func successfulUnregisterPrecedesDeletionAndLeavesOtherFlavor() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = BrowserNativeInstallation.browserDirectory(home: home, flavor: .current)
        let browser = BrowserNativeStore(directory: directory)
        try browser.activate()
        let other: CurfewFlavor = CurfewFlavor.current == .development ? .production : .development
        let otherDirectory = BrowserNativeInstallation.browserDirectory(home: home, flavor: other)
        let otherBrowser = BrowserNativeStore(directory: otherDirectory)
        try otherBrowser.activate()
        let service = UninstallBackgroundServiceStub()
        service.beforeUnregister = {
            let active = try browser.isActive()
            #expect(active)
        }
        let manager = BackgroundServiceManager(service: service, retireLegacyGuard: {})

        var stopped = false
        let outcome = UninstallCoordinator.performUninstall(
            home: home,
            defaultsSuiteName: "studio.hypertext.curfew.tests.\(UUID().uuidString)",
            unregisterServices: { [] },
            eraseKeychainService: { _ in },
            backgroundService: manager,
            onRecoveryStopped: { stopped = true }
        )

        #expect(service.unregisterCount == 1)
        #expect(outcome.allSucceeded)
        #expect(stopped)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(try otherBrowser.isActive())
    }

    @Test func shellUninstallAbortsWhenServiceRefusesToStop() throws {
        let fixture = try ShellUninstallFixture(exitStatus: 42)
        defer { fixture.cleanUp() }
        let status = try fixture.run()
        #expect(status != 0)
        let operation = try String(contentsOf: fixture.home.appendingPathComponent("operation"))
        #expect(operation
            .trimmingCharacters(in: .whitespacesAndNewlines) == "--unregister-background-service")
        #expect(FileManager.default.fileExists(atPath: fixture.state.path))
    }

    @Test func shellDevelopmentUninstallLeavesProductionState() throws {
        let fixture = try ShellUninstallFixture(exitStatus: 0, development: true)
        defer { fixture.cleanUp() }
        let productionState = fixture.home.appendingPathComponent(
            "Library/Application Support/Curfew/enforcement-runtime.json"
        )
        try FileManager.default.createDirectory(
            at: productionState.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("production budget".utf8).write(to: productionState)
        let status = try fixture.run()
        #expect(status == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.state.path))
        #expect(FileManager.default.fileExists(atPath: productionState.path))
        let operation = try String(contentsOf: fixture.home.appendingPathComponent("operation"))
        #expect(operation
            .trimmingCharacters(in: .whitespacesAndNewlines) == "--unregister-background-service")
    }

    @Test func hostNeverRegistersOrUnregistersARealService() throws {
        let manager = BackgroundServiceManager()
        #expect(!manager.isAvailable)
        manager.register()
        try manager.unregister()
        #expect(manager.status == .notRegistered)
        #expect(manager.lastError == nil)
    }
}

@MainActor
private final class UninstallBackgroundServiceStub: AppServiceControlling {
    var status: SMAppService.Status = .enabled
    var failsUnregister = false
    var unregisterCount = 0
    var beforeUnregister: (() throws -> Void)?

    func register() throws {}

    func unregister() throws {
        unregisterCount += 1
        try beforeUnregister?()
        if failsUnregister {
            throw CocoaError(.fileWriteNoPermission)
        }
        status = .notRegistered
    }
}

private struct ShellUninstallFixture {
    let home: URL
    let bundle: URL
    let state: URL
    let development: Bool

    init(exitStatus: Int, development: Bool = false) throws {
        self.development = development
        self.home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.bundle = home.appendingPathComponent("Fixture.app")
        self.state = home.appendingPathComponent(
            "Library/Application Support/Curfew\(development ? CurfewFlavor.development.storageDisplaySuffix : "")/enforcement-runtime.json"
        )
        let executable = bundle.appendingPathComponent("Contents/MacOS/Curfew")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: state.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("spent budget".utf8).write(to: state)
        try Data("#!/bin/sh\nprintf '%s\\n' \"$1\" > \"$HOME/operation\"\nexit \(exitStatus)\n"
            .utf8)
            .write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let identifier = (development ? CurfewFlavor.development : .production).bundleIdentifier
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundleExecutable": "Curfew"],
            format: .xml, options: 0
        )
        try info.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
    }

    func run() throws -> Int32 {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        let realHome = NSHomeDirectory().replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let sandbox = "(version 1)(allow default)" +
            "(deny process-exec (subpath \"/Applications\") (literal \"/usr/bin/sudo\") " +
            "(literal \"/bin/launchctl\") (literal \"/usr/bin/defaults\"))" +
            "(deny file-write* (subpath \"/Library\") (subpath \"\(realHome)\"))"
        process.arguments = [
            "-p", sandbox, "/bin/bash",
            root.appendingPathComponent("scripts/uninstall.sh").path,
            "--force",
            "--app-bundle",
            bundle.path
        ] +
            (development ? ["--development"] : [])
        process.environment = ProcessInfo.processInfo.environment
            .merging(["HOME": home.path]) { _, new in new }
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: home)
    }
}
