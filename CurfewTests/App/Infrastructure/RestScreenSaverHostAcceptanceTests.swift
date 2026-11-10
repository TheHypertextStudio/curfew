import AppKit
@testable import Curfew
@testable import CurfewAtmosphere
import CurfewKit
import Darwin
import ScreenSaver
import XCTest

/// Opt-in process acceptance on an exclusively reserved Mac. Normal CI never
/// opens system UI or changes the user's selected screensaver.
@MainActor
final class RestScreenSaverHostAcceptanceTests: XCTestCase {
    func testSelectedCompanionAcknowledgesAppPublications() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CURFEW_SAVER_HOST_ACCEPTANCE"] == "1",
            "Requires the reserved native session and Curfew selected in Screen Saver Settings."
        )
        let restore = try preservePresentation()
        defer { restore() }
        let preferences = try RestScreenSaverPreferences.system()
        let publisher = RestCompanionPublisher(
            readOwnedImage: { _ in nil },
            publish: { try preferences.publish(snapshot: $0, imageData: $1) }
        )
        let now = Date()
        for palette in [RestAppearancePreferences.Palette.warmAmber, .coolTwilight] {
            let scene = scene(palette: palette, now: now)
            await publisher.reconcile(snapshot: scene, allowsPublication: true)
            XCTAssertEqual(publisher.status, .publicationWritten)
            let nonce = try preferences.requestReadback()
            XCTAssertFalse(preferences.hasAcknowledgedCurrentPublication())
            let acknowledged = try await waitForHost(preferences)
            XCTAssertTrue(
                acknowledged,
                "The actual host did not acknowledge the fresh publication."
            )
            guard acknowledged else { return }
            let receipt = XCTAttachment(string: "palette=\(palette.rawValue) nonce=\(nonce)")
            receipt.name = "Companion process readback"
            receipt.lifetime = .keepAlways
            add(receipt)
        }
    }

    func testSelectedCompanionEntersFullScreenAndReturnsRepeatedly() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CURFEW_SAVER_FULL_SCREEN_ACCEPTANCE"] == "1",
            "Requires an exclusive native session and Curfew selected in Screen Saver Settings."
        )
        let restore = try preservePresentation()
        defer { restore() }
        let preferences = try RestScreenSaverPreferences.system()
        for palette in [RestAppearancePreferences.Palette.warmAmber, .coolTwilight] {
            try preferences.publish(snapshot: scene(palette: palette, now: Date()), imageData: nil)
            let launcher = RestSaverLauncher.live(preferences: preferences)
            let result = await launcher.launch()
            XCTAssertEqual(result, .started, "Actual full-screen companion launch must succeed.")
            guard result == .started else { return }
            let pid = try XCTUnwrap(launcher.ownedProcess)
            defer { launcher.stopOwned() }
            XCTAssertTrue(preferences.hasFullScreenAcknowledgement())
            XCTAssertFalse(launcher.hasReturned)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Actual full-screen companion — \(palette.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            launcher.stopOwned()
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while NSRunningApplication(processIdentifier: pid)?.isTerminated == false,
                  ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertNotEqual(NSRunningApplication(processIdentifier: pid)?.isTerminated, false)
        }
    }

    private func preservePresentation() throws -> () -> Void {
        let files = try RestPresentationFiles(directory: RestPresentationFiles.systemDirectory())
        let slots: [RestCompanionPresentationStore.Slot] = [
            .appearance,
            .occurrence,
            .readbackRequest
        ]
        let originalFiles = try slots.map {
            try ($0, files.read($0, maximum: RestCompanionPresentationStore.maximumAppearanceBytes))
        }
        let directoryExisted = FileManager.default.fileExists(atPath: files.directory.path)
        let defaults = try XCTUnwrap(ScreenSaverDefaults(
            forModuleWithName: RestScreenSaverPreferences.moduleIdentifier
        ))
        let keys = ["appearance", "occurrence", "readbackRequest", "acknowledgement"]
            .map { "rest.presentation.v1.\($0)" }
        let original = keys.map { ($0, defaults.object(forKey: $0)) }
        return {
            for (slot, bytes) in originalFiles {
                do {
                    if let bytes {
                        try files.write(slot, bytes: bytes)
                    } else {
                        try files.remove(slot)
                    }
                } catch {
                    XCTFail("Original presentation file could not be restored: \(error)")
                }
            }
            if !directoryExisted {
                _ = rmdir(files.directory.path)
            }
            for (key, value) in original {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            XCTAssertTrue(
                defaults.synchronize(),
                "Original presentation preferences must be restored."
            )
        }
    }

    private func scene(palette: RestAppearancePreferences.Palette, now: Date) -> RestSceneSnapshot {
        RestSceneSnapshot(
            version: 1, expiresAt: now.addingTimeInterval(4500),
            appearance: RestAppearancePreferences(
                palette: palette, message: "Curfew native verification", saverMessageEnabled: true
            ),
            lockDate: now.addingTimeInterval(-3600), unlockDate: now.addingTimeInterval(900)
        )
    }

    private func waitForHost(_ preferences: RestScreenSaverPreferences) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(90))
        while !preferences.hasAcknowledgedCurrentPublication(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }
        return preferences.hasAcknowledgedCurrentPublication()
    }
}
