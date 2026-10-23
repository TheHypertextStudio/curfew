@testable import CurfewAtmosphere
import CurfewKit
import Foundation
import Testing

struct RestSandboxExchangeTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func withStores(_ body: (UserDefaults, UserDefaults, RestPresentationFiles) throws
        -> Void) throws {
        let appName = "RestSandboxApp.\(UUID().uuidString)"
        let hostName = "RestSandboxHost.\(UUID().uuidString)"
        let app = try #require(UserDefaults(suiteName: appName))
        let host = try #require(UserDefaults(suiteName: hostName))
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("RestSandboxFiles-\(UUID().uuidString)")
        defer {
            app.removePersistentDomain(forName: appName)
            host.removePersistentDomain(forName: hostName)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(app, host, RestPresentationFiles(directory: directory))
    }

    private var scene: RestSceneSnapshot {
        .init(
            version: 1,
            expiresAt: now.addingTimeInterval(3600),
            appearance: .init(
                palette: .warmAmber,
                message: "Local only",
                saverMessageEnabled: true
            ),
            lockDate: now.addingTimeInterval(-60),
            unlockDate: now.addingTimeInterval(1800)
        )
    }

    @Test("Isolated sandbox defaults receive only the validated presentation export")
    func sandboxReadback() throws {
        try withStores { app, host, files in
            let publisher = RestScreenSaverPreferences(defaults: app, files: files, host: false)
            let receiver = RestScreenSaverPreferences(defaults: host, files: files, host: true)
            try publisher.publish(snapshot: scene, imageData: nil)
            let nonce = try publisher.requestReadback()
            let publication = try #require(receiver.read(at: now))
            #expect(publication.presentation.appearance.palette == .warmAmber)
            #expect(publication.readbackNonce == nonce)
            #expect(host.object(forKey: RestScreenSaverPreferences.Keys.appearance) is Data)
        }
    }

    @Test(
        "Host emits a bounded fresh receipt across isolated preference containers"
    )
    func isolatedAcknowledgement() throws {
        try withStores { app, host, files in
            let publisher = RestScreenSaverPreferences(defaults: app, files: files, host: false)
            try publisher.publish(snapshot: scene, imageData: nil)
            _ = try publisher.requestReadback()
            // Model a host which has already persisted this valid generation.
            for key in [
                RestScreenSaverPreferences.Keys.appearance,
                RestScreenSaverPreferences.Keys.occurrence,
                RestScreenSaverPreferences.Keys.readbackRequest
            ] {
                host.set(app.object(forKey: key), forKey: key)
            }
            var emitted: Data?
            let receiver = RestScreenSaverPreferences(
                defaults: host,
                files: files,
                host: true,
                postReceipt: { emitted = $0 }
            )
            let publication = try #require(receiver.read(at: now))
            try receiver.acknowledge(publication)
            let receipt = try #require(emitted)
            #expect(receipt.count <= RestCompanionPresentationStore.maximumOccurrenceBytes)
            #expect(!publisher.hasAcknowledgedCurrentPublication())
            #expect(publisher.acceptHostAcknowledgement(receipt))
            #expect(publisher.hasAcknowledgedCurrentPublication())
            _ = try publisher.requestReadback()
            #expect(!publisher.acceptHostAcknowledgement(receipt))
            #expect(!publisher.hasAcknowledgedCurrentPublication())
        }
    }

    @Test("Preview readback cannot claim the matching companion appeared full screen")
    func fullScreenReceipt() throws {
        try withStores { app, host, files in
            let publisher = RestScreenSaverPreferences(defaults: app, files: files, host: false)
            try publisher.publish(snapshot: scene, imageData: nil)
            _ = try publisher.requestReadback()
            var emitted: Data?
            let preview = RestScreenSaverPreferences(
                defaults: host, files: files, host: true, postReceipt: { emitted = $0 }
            )
            try preview.acknowledge(#require(preview.read(at: now)))
            #expect(try publisher.acceptHostAcknowledgement(#require(emitted)))
            #expect(!publisher.hasFullScreenAcknowledgement())
            let fullScreen = RestScreenSaverPreferences(
                defaults: host, files: files, host: true, postReceipt: { emitted = $0 },
                fullScreenHost: true
            )
            try fullScreen.acknowledge(#require(fullScreen.read(at: now)))
            #expect(try publisher.acceptHostAcknowledgement(#require(emitted)))
            #expect(publisher.hasFullScreenAcknowledgement())
            _ = try publisher.requestReadback()
            #expect(!publisher.hasFullScreenAcknowledgement())
            #expect(try !publisher.acceptHostAcknowledgement(#require(emitted)))
        }
    }

    @Test("A rejected file publication retries without stranding a defaults generation")
    func retryAfterFileFailure() throws {
        try withStores { app, host, files in
            try FileManager.default.createDirectory(
                at: files.directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o755]
            )
            let publisher = RestScreenSaverPreferences(defaults: app, files: files, host: false)
            #expect(throws: (any Error).self) {
                try publisher.publish(snapshot: scene, imageData: nil)
            }
            #expect(app.object(forKey: RestScreenSaverPreferences.Keys.appearance) == nil)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: files.directory.path
            )
            try publisher.publish(snapshot: scene, imageData: nil)
            let receiver = RestScreenSaverPreferences(defaults: host, files: files, host: true)
            let publication = try #require(receiver.read(at: now))
            #expect(publication.presentation.appearance.palette == .warmAmber)
        }
    }

    @Test("Unsolicited, malformed and oversized receipts cannot become host acceptance")
    func invalidReceipts() throws {
        try withStores { app, _, files in
            let publisher = RestScreenSaverPreferences(defaults: app, files: files, host: false)
            for bytes in [Data(), Data("{}".utf8), Data(repeating: 0, count: 4097)] {
                #expect(!publisher.acceptHostAcknowledgement(bytes))
                #expect(app.object(forKey: RestScreenSaverPreferences.Keys.acknowledgement) == nil)
            }
        }
    }
}
