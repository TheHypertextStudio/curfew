#if DEBUG
    import AppKit
    @testable import Curfew
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
    /// Output lands in `build/snapshots/curfew-<name>.png` (gitignored). The
    /// directory is resolved from `#filePath`, so the test doesn't depend on the
    /// working directory or any environment plumbing.
    @MainActor
    final class DestinationSnapshotTests: XCTestCase {
        /// Renders the three spine destinations (Today, Schedule, Journal) with
        /// a mid-workday demo state so the countdown, schedule, and weekly
        /// streak all read as populated.
        func testRenderSpineDestinations() throws {
            let outputDirectory = try Self.snapshotsDirectory()

            let model = Self.demoModel()

            try renderBoth(
                ScheduleContent().environment(model),
                named: "schedule",
                width: 880,
                to: outputDirectory
            )
            try renderBoth(
                TodaySundownView(),
                named: "today-sundown",
                width: 900,
                to: outputDirectory
            )
            try renderBoth(
                emptyToday(),
                named: "today-empty",
                width: 900,
                to: outputDirectory
            )
            try renderBoth(
                JournalSundownView(),
                named: "journal-sundown",
                width: 900,
                to: outputDirectory
            )
            try renderBoth(
                JournalReflectionsView(
                    reflections: [],
                    referenceDate: model.currentTime,
                    onConfigurePrompts: {}
                ).environment(model),
                named: "journal-reflections",
                width: 900,
                to: outputDirectory
            )
            try renderBoth(
                ContentView().environment(model),
                named: "menubar",
                width: 320,
                to: outputDirectory
            )
            try renderBoth(
                LockoutSundownView(),
                named: "lockout-sundown",
                width: 1440,
                height: 900,
                to: outputDirectory
            )

            print("==> Snapshots written to \(outputDirectory.path)")
        }

        /// A demo model pinned to a flattering mid-workday state.
        private static func demoModel() -> CurfewAppModel {
            let model = CurfewAppModel.demoModel()
            model.currentTime = DemoFixture.referenceTime(for: .overview, now: Date())
            model.state = DemoFixture.evaluation(for: .overview, now: model.currentTime)
            return model
        }

        /// The not-set-up Today state (empty hero + accessibility warning).
        private func emptyToday() -> TodaySundownView {
            TodaySundownView(
                greeting: "Good evening",
                timeRemaining: "",
                emptyNote: "Set your schedule to begin.",
                statusLine: "Finish setting up Curfew",
                statusDetail: "Set your schedule, then turn Curfew on.",
                showAccessibilityWarning: true,
                primaryActionLabel: "Finish Setup"
            )
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
        private func render(
            _ view: some View,
            named name: String,
            width: CGFloat,
            height: CGFloat? = nil,
            appearance: NSAppearance.Name,
            to directory: URL
        ) throws {
            let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
            let content = view
                .environment(\.colorScheme, scheme)
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

        /// `<repo>/build/snapshots`, derived from this file's location so the
        /// output path is stable regardless of the test's working directory.
        private static func snapshotsDirectory() throws -> URL {
            var url = URL(fileURLWithPath: #filePath)
            url.deleteLastPathComponent() // Snapshots/
            url.deleteLastPathComponent() // CurfewTests/
            url.deleteLastPathComponent() // <repo>/
            let directory = url
                .appendingPathComponent("build", isDirectory: true)
                .appendingPathComponent("snapshots", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        }
    }
#endif
import CurfewKit
