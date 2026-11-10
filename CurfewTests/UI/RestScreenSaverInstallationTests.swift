@testable import Curfew
import Foundation
import Testing

@MainActor
struct RestScreenSaverInstallationTests {
    @Test("Missing companion offers no installation request")
    func missingCompanion() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let recorder = Recorder()
        let service = RestScreenSaverInstallation(
            locations: .init(bundledSaver: nil, userInstallationDirectory: fixture.userDirectory),
            open: { recorder.opened.append($0); return true },
            removeOwnedSaver: { recorder.removed.append($0) }
        )
        #expect(service.inspect() == .missingCompanion)
        #expect(service.requestInstallation() == .missingCompanion)
        #expect(recorder.opened.isEmpty)
    }

    @Test("Bundle metadata determines availability without loading executable code")
    func availableCompanion() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.bundle(at: fixture.bundled, version: "2.0")
        #expect(fixture.service(recorder: Recorder()).inspect() == .available(version: "2.0"))
    }

    @Test("Matching installed version is independent of app version")
    func matchingInstalledVersion() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.bundle(at: fixture.bundled, version: "2.0")
        try fixture.bundle(at: fixture.installed, version: "2.0")
        #expect(fixture.service(recorder: Recorder()).inspect() == .installed(version: "2.0"))
    }

    @Test("Every unequal companion version requires an explicit update action")
    func versionMismatch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.bundle(at: fixture.bundled, version: "2.0")
        try fixture.bundle(at: fixture.installed, version: "1.9")
        let recorder = Recorder()
        let service = fixture.service(recorder: recorder)
        #expect(service.inspect() == .versionMismatch(bundled: "2.0", installed: "1.9"))
        #expect(recorder.opened.isEmpty)
        #expect(service.requestInstallation() == .installRequestAccepted(version: "2.0"))
        #expect(recorder.opened == [fixture.bundled])
        #expect(service.inspect() == .versionMismatch(bundled: "2.0", installed: "1.9"))
    }

    @Test("An accepted installer open is a request receipt, not installed proof")
    func acceptedInstallationRequest() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.bundle(at: fixture.bundled, version: "2.0")
        let recorder = Recorder()
        let service = fixture.service(recorder: recorder)
        #expect(service.requestInstallation() == .installRequestAccepted(version: "2.0"))
        #expect(recorder.opened == [fixture.bundled])
        #expect(!FileManager.default.fileExists(atPath: fixture.installed.path))
        #expect(service.inspect() == .available(version: "2.0"))
    }

    @Test("System rejection remains actionable and does not imply installation")
    func rejectedInstallationRequest() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.bundle(at: fixture.bundled, version: "2.0")
        let recorder = Recorder()
        recorder.acceptOpen = false
        guard case .operationRejected(let reason) = fixture.service(recorder: recorder)
            .requestInstallation() else {
            Issue.record("Expected an explicit rejected installer request")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test("Settings selection delegates to the public preference URL")
    func openSettings() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let recorder = Recorder()
        _ = fixture.service(recorder: recorder).openSystemSettings()
        #expect(recorder.opened == [RestScreenSaverInstallation.settingsURL])
    }

    @Test("Removal delegates only the validated owned user installation")
    func removeOwnedInstallation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.bundle(at: fixture.bundled, version: "2.0")
        try fixture.bundle(at: fixture.installed, version: "1.9")
        let recorder = Recorder()
        _ = fixture.service(recorder: recorder).removeInstallation()
        #expect(recorder.removed == [fixture.installed])
    }

    @Test("Foreign bundle identifiers and symlink leaves never reach removal")
    func rejectForeignAndSymlinkRemoval() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.bundle(at: fixture.installed, version: "1.0", identifier: "other.vendor.saver")
        let recorder = Recorder()
        let service = fixture.service(recorder: recorder)
        guard case .operationRejected = service.removeInstallation() else {
            Issue.record("Foreign bundle removal must be rejected")
            return
        }
        try FileManager.default.removeItem(at: fixture.installed)
        try fixture.bundle(at: fixture.bundled, version: "2.0")
        try FileManager.default.createSymbolicLink(
            at: fixture.installed,
            withDestinationURL: fixture.bundled
        )
        guard case .operationRejected = service.removeInstallation() else {
            Issue.record("Symlink removal must be rejected")
            return
        }
        #expect(recorder.removed.isEmpty)
    }

    @Test("Removal failures preserve a distinct rejected outcome")
    func rejectedRemoval() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.bundle(at: fixture.installed, version: "2.0")
        let recorder = Recorder()
        recorder.rejectRemoval = true
        guard case .operationRejected(let reason) = fixture.service(recorder: recorder)
            .removeInstallation() else {
            Issue.record("Expected rejected removal")
            return
        }
        #expect(!reason.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.installed.path))
    }

    @Test("Invalid companion metadata never reaches the installer")
    func rejectInvalidCompanionMetadata() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let recorder = Recorder()
        let service = fixture.service(recorder: recorder)
        let contents = fixture.bundled.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = contents.appendingPathComponent("Info.plist")
        // Existing .saver directory with no metadata is distinct from an absent companion.
        expectRejected(service.requestInstallation())
        try Data("not a property list".utf8).write(to: plist)
        expectRejected(service.requestInstallation())
        try fixture.bundle(at: fixture.bundled, version: "2.0", packageType: "APPL")
        expectRejected(service.requestInstallation())
        try fixture.bundle(at: fixture.bundled, version: "   ")
        expectRejected(service.requestInstallation())
        #expect(recorder.opened.isEmpty)
    }

    @Test("Invalid installed metadata cannot authorize removal")
    func rejectInvalidInstalledMetadata() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let recorder = Recorder()
        let service = fixture.service(recorder: recorder)
        let contents = fixture.installed.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = contents.appendingPathComponent("Info.plist")
        expectRejected(service.removeInstallation())
        try Data("not a property list".utf8).write(to: plist)
        expectRejected(service.removeInstallation())
        try fixture.bundle(at: fixture.installed, version: "2.0", packageType: "APPL")
        expectRejected(service.removeInstallation())
        try fixture.bundle(at: fixture.installed, version: "")
        expectRejected(service.removeInstallation())
        #expect(recorder.removed.isEmpty)
    }

    @Test("A redirected installation parent cannot authorize deletion outside the owned directory")
    func rejectSymlinkInstallationParent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let outside = fixture.root.appendingPathComponent("Foreign/Screen Savers")
        try fixture.bundle(at: outside.appendingPathComponent("Curfew.saver"), version: "2.0")
        try FileManager.default.removeItem(at: fixture.userDirectory)
        try FileManager.default.createSymbolicLink(
            at: fixture.userDirectory,
            withDestinationURL: outside
        )
        let recorder = Recorder()
        expectRejected(fixture.service(recorder: recorder).removeInstallation())
        #expect(recorder.removed.isEmpty)
        #expect(FileManager.default
            .fileExists(atPath: outside.appendingPathComponent("Curfew.saver").path))
    }

    private func expectRejected(_ state: RestScreenSaverInstallation.State) {
        guard case .operationRejected(let reason) = state else {
            Issue.record("Invalid metadata or unsafe location must produce explicit rejection")
            return
        }
        #expect(!reason.isEmpty)
    }

    private final class Recorder {
        var opened: [URL] = []
        var removed: [URL] = []
        var acceptOpen = true
        var rejectRemoval = false
    }

    private struct Fixture {
        let root: URL
        let bundled: URL
        let userDirectory: URL
        var installed: URL {
            userDirectory.appendingPathComponent("Curfew.saver")
        }

        init() throws {
            self.root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent(UUID().uuidString)
            self.bundled = root.appendingPathComponent("App/Contents/Resources/Curfew.saver")
            self.userDirectory = root.appendingPathComponent("User/Library/Screen Savers")
            try FileManager.default.createDirectory(
                at: userDirectory,
                withIntermediateDirectories: true
            )
        }

        func bundle(
            at url: URL,
            version: String,
            identifier: String = RestScreenSaverInstallation.moduleIdentifier,
            packageType: String = "BNDL"
        ) throws {
            let contents = url.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: [
                "CFBundleIdentifier": identifier,
                "CFBundleShortVersionString": version,
                "CFBundlePackageType": packageType
            ], format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }

        func service(recorder: Recorder) -> RestScreenSaverInstallation {
            RestScreenSaverInstallation(
                locations: .init(bundledSaver: bundled, userInstallationDirectory: userDirectory),
                open: { recorder.opened.append($0); return recorder.acceptOpen },
                removeOwnedSaver: {
                    recorder.removed.append($0)
                    if recorder.rejectRemoval {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                }
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
