#if DEBUG
    import AppKit
    @testable import Curfew
    import CurfewKit
    import SwiftUI
    import XCTest

    /// Headless snapshot tier for the marketing / debug capture system.
    ///
    /// Renders each main-window destination straight to a PNG with SwiftUI's
    /// `ImageRenderer`, driven by the demo fixture. Unlike `MarketingCaptureTests`
    /// (the XCUITest tier), this needs no UI-test-runner authorization and no
    /// Screen Recording permission, never takes over the desktop, and runs on a
    /// headless CI machine — so it's the low-friction way to *see* a UX change.
    ///
    /// Output lands in `build/screenshots/curfew-<name>.png` (gitignored). The
    /// directory is resolved from `#filePath`, so the test doesn't depend on the
    /// working directory or any environment plumbing.
    @MainActor
    final class DestinationSnapshotTests: XCTestCase {
        func testRenderCurrentMarketingScreens() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            try renderHosted(
                JournalView().environment(model),
                named: "marketing-journal", width: 1080, height: 720, to: directory
            )
            try renderHosted(
                ScheduleView().environment(model),
                named: "marketing-schedule", width: 1080, height: 720, to: directory
            )
            try render(
                LockSnapshotTests.lockWindow(LockSnapshotTests.lockedModel(now: model.currentTime
                        .addingTimeInterval(7 * 3600))),
                named: "marketing-lockout", width: 960, height: 600, to: directory
            )
        }

        func testRenderPresenceReminderControls() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            // The fixture is never started, so stored intent does not open the camera.
            model.settings.presence.cameraEnabled = true
            model.settings.presence.warnsWhenDistracted = true
            XCTAssertFalse(model.isPresenceCameraLive)
            try renderHosted(
                SettingsView(initialSection: .presence).environment(model),
                named: "copy-presence-reminders", width: 760, height: 580, to: directory
            )
            XCTAssertFalse(model.isPresenceCameraLive)
        }

        /// Native controls need an AppKit host for rasterization.
        func renderHosted(
            _ view: some View, named name: String, width: CGFloat, height: CGFloat,
            settlingTime: TimeInterval = 0.1,
            appearance: NSAppearance.Name = .aqua,
            to directory: URL
        ) throws {
            let host = NSHostingView(rootView: view.environment(
                \.colorScheme, appearance == .darkAqua ? .dark : .light
            )
            // Headless rasterisers do not run the sky's Metal shader; draw the
            // same scene with the CPU reference renderer so captures are true.
            .environment(\.horizonSkyRendering, .reference)
            .frame(
                width: width, height: height, alignment: .topLeading
            ))
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.appearance = NSAppearance(named: appearance)
            host.appearance = window.appearance
            window.contentView = host
            host.frame = frame
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(settlingTime))
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("curfew-\(name).png"))
        }

        func testRenderAccessibilityPermissionStates() throws {
            let directory = try Self.snapshotsDirectory()
            let suite = "CurfewPermissionSnapshot-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = CurfewSettingsStore(defaults: defaults)
            store.save(DemoFixture.demoSettings())
            let trust = FakeAccessibilityAuthorization(trusted: false)
            let model = CurfewAppModel(
                settingsStore: store,
                appRouter: AppRouterSpy(),
                activityRecorder: NullActivityRecording(),
                lockoutDeadlineStore: .ephemeralForTesting(),
                accessibilityAuthorization: trust
            )
            model.state = DemoFixture.evaluation(for: .overview, now: Date())
            XCTAssertFalse(model.isAccessibilityTrusted)
            try render(
                TodayView().environment(model),
                named: "permission-missing", width: 900, height: 680, to: directory
            )
            trust.trusted = true
            model.refreshAccessibilityTrust()
            XCTAssertTrue(model.isAccessibilityTrusted)
            try render(
                TodayView().environment(model),
                named: "permission-granted", width: 900, height: 680, to: directory
            )
        }

        /// Renders the spine destinations with a mid-workday demo state so the
        /// countdown and schedule read as populated. The Journal has its own
        /// renders in `JournalSnapshotTests`.
        func testRenderSpineDestinations() throws {
            let outputDirectory = try Self.snapshotsDirectory()
            let model = Self.demoModel()

            try renderWorkspaceDestinations(model: model, to: outputDirectory)
            try renderAtmosphericOverlays(model: model, to: outputDirectory)

            print("==> Snapshots written to \(outputDirectory.path)")
        }

        private func renderWorkspaceDestinations(
            model: CurfewAppModel,
            to outputDirectory: URL
        ) throws {
            try renderBoth(
                ScheduleContent().environment(model),
                named: "schedule",
                width: 880,
                to: outputDirectory
            )
        }

        private func renderAtmosphericOverlays(
            model: CurfewAppModel,
            to outputDirectory: URL
        ) throws {
            try renderBoth(
                MainWindowView().environment(model),
                named: "main-window",
                width: 1080,
                height: 720,
                to: outputDirectory
            )
        }

        /// A demo model pinned to a flattering mid-workday state.
        static func demoModel() -> CurfewAppModel {
            let model = CurfewAppModel.demoModel()
            model.currentTime = DemoFixture.referenceTime(for: .overview, now: Date())
            model.state = DemoFixture.evaluation(for: .overview, now: model.currentTime)
            return model
        }

        /// Renders `view` in both Light and Dark appearance, writing
        /// `curfew-<name>-light.png` and `curfew-<name>-dark.png`. Every surface
        /// is reviewed in both modes, so both variants are produced side by side.
        private func renderBoth(
            _ view: some View,
            named name: String,
            width: CGFloat,
            height: CGFloat? = nil,
            to directory: URL
        ) throws {
            try render(
                view,
                named: "\(name)-light",
                width: width,
                height: height,
                appearance: .aqua,
                to: directory
            )
            try render(
                view,
                named: "\(name)-dark",
                width: width,
                height: height,
                appearance: .darkAqua,
                to: directory
            )
        }

        /// Renders `view` at a fixed `width` (natural height, 2× scale) onto the
        /// canvas background and writes it as a PNG. The render runs inside the
        /// requested `appearance` so `CurfewTheme`'s dynamic `NSColor` providers
        /// resolve for the right mode, and the SwiftUI `colorScheme` environment
        /// is set to match for any native-adaptive views. Throws rather than
        /// crashes if the platform hands back no bitmap, so a render hiccup can't
        /// take down the suite.
        func render(
            _ view: some View,
            named name: String,
            width: CGFloat,
            height: CGFloat? = nil,
            appearance: NSAppearance.Name = .aqua,
            to directory: URL
        ) throws {
            let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
            let content = view
                .environment(\.colorScheme, scheme)
                .environment(\.horizonSkyRendering, .reference)
                .frame(width: width, height: height, alignment: .topLeading)
                .background(CurfewTheme.canvas)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 2

            // Resolve dynamic colours against the target appearance: `nsImage`
            // draws synchronously, so wrapping it sets `currentDrawingAppearance`
            // for the NSColor providers `CurfewTheme` is built on.
            var png: Data?
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff) {
                    png = bitmap.representation(using: .png, properties: [:])
                }
            }

            guard let png else {
                throw XCTSkip("ImageRenderer produced no bitmap for \(name)")
            }

            try png.write(to: directory.appendingPathComponent("curfew-\(name).png"))
        }

        /// `<repo>/build/screenshots`, derived from this file's location so the
        /// output path is stable regardless of the test's working directory.
        static func snapshotsDirectory() throws -> URL {
            var url = URL(fileURLWithPath: #filePath)
            url.deleteLastPathComponent() // Snapshots/
            url.deleteLastPathComponent() // CurfewTests/
            url.deleteLastPathComponent() // <repo>/
            let directory = url
                .appendingPathComponent("build", isDirectory: true)
                .appendingPathComponent("screenshots", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        }
    }
#endif
