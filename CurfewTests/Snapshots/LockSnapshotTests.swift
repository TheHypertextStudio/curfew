#if DEBUG
    import AppKit
    @testable import Curfew
    import CurfewKit
    import SwiftUI
    import XCTest

    /// Writes the warnings, the lock and its panels to
    /// `build/screenshots/curfew-lock-*.png` and `curfew-notice-*.png` for
    /// review against the Horizon prototype. The lock is always the night sky,
    /// so it renders once; the notice floats over the desktop and renders over
    /// a light and a dark desktop. The headless rasteriser has no compositor
    /// for Liquid Glass, so captures use the defined Reduce Transparency
    /// alternative, where glass becomes a solid night panel.
    @MainActor
    final class LockSnapshotTests: XCTestCase {
        private static let calendar = Calendar.current
        private static let day = calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 16
        ))!

        private static func at(_ hour: Int, _ minute: Int, nextDay: Bool = false) -> Date {
            let base = nextDay ? calendar.date(byAdding: .day, value: 1, to: day)! : day
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }

        /// A demo model locked from 6 PM to 7 AM, at `now`.
        static func lockedModel(now: Date) -> CurfewAppModel {
            let model = CurfewAppModel.demoModel()
            model.currentTime = now
            model.state = CurfewEvaluation(
                phase: .locked, warningStage: .lockout, minutesRemaining: 0,
                canRequestExtension: false, lockDate: at(18, 0), unlockDate: at(7, 0, nextDay: true)
            )
            model.lockoutMessage = VoicePack.standard.lockedHeadline
            return model
        }

        /// The full lock window for `model`, settled.
        static func lockWindow(_ model: CurfewAppModel) -> some View {
            let display = RestDisplayPresentation()
            display.isVisible = true
            let scene = LockScene()
            scene.settle(at: model.currentTime)
            return RestScreenView(model: model, display: display, scene: scene)
                .environment(\.eveningOneThingPreview, "Ship the billing migration")
        }

        func testRenderLockStates() throws {
            let directory = try DestinationSnapshotTests.snapshotsDirectory()

            let night = Self.lockedModel(now: Self.at(21, 41))
            try render(Self.lockWindow(night), named: "lock-night", to: directory)

            let closeOut = Self.lockedModel(now: Self.at(18, 4))
            closeOut.reflectionState.isEveningReflectionPending = true
            try render(Self.lockWindow(closeOut), named: "lock-close-out", to: directory)

            let lead = Self.lockedModel(now: Self.at(6, 48, nextDay: true))
            try render(Self.lockWindow(lead), named: "lock-lead-in", to: directory)

            let reason = "The production deploy is failing and I am the only one on call tonight."
            for (name, text, waited) in [
                ("typing", String(reason.prefix(32)), 1.0),
                ("cooling", reason, 250.0),
                ("ready", reason, 400.0)
            ] {
                let model = Self.lockedModel(now: Self.at(21, 41))
                model.overrideRequestedAt = model.currentTime.addingTimeInterval(-waited)
                model.overrideReasonDraft = text
                model.isOverrideComposerVisible = true
                try render(Self.lockWindow(model), named: "lock-override-\(name)", to: directory)
            }
        }

        func testRenderWarningNotices() throws {
            let directory = try DestinationSnapshotTests.snapshotsDirectory()
            let curfew = Self.at(18, 0)
            for (stage, minutes) in [
                (WarningStage.thirtyMinutes, 30), (.fifteenMinutes, 15), (.fiveMinutes, 5), (
                    .oneMinute,
                    1
                )
            ] {
                let state = WarningNoticeState()
                state.stage = stage
                state.curfew = curfew
                let now = curfew.addingTimeInterval(-Double(minutes) * 60 + 1)
                for (appearance, backdrop) in [
                    (NSAppearance.Name.aqua, Color(white: 0.93)),
                    (.darkAqua, Color(white: 0.12))
                ] {
                    let notice = ZStack(alignment: .topTrailing) {
                        backdrop
                        WarningNoticeView(state: state, now: now)
                            .environment(\.colorScheme, .dark)
                            .frame(
                                width: WarningNoticeCoordinator.size.width,
                                height: WarningNoticeCoordinator.size.height
                            )
                            .padding(CurfewSpacing.xLarge)
                    }
                    let suffix = appearance == .darkAqua ? "dark" : "light"
                    try render(
                        notice, named: "notice-\(minutes)-\(suffix)", width: 480, height: 200,
                        appearance: appearance, to: directory
                    )
                }
            }
        }

        private func render(
            _ view: some View, named name: String, width: CGFloat = 1440, height: CGFloat = 900,
            appearance: NSAppearance.Name = .darkAqua, to directory: URL
        ) throws {
            let host = NSHostingView(rootView: view
                .environment(\.horizonSkyRendering, .reference)
                .environment(\._accessibilityReduceTransparency, true)
                .transaction { $0.disablesAnimations = true }
                .frame(width: width, height: height))
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(
                contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.appearance = NSAppearance(named: appearance)
            host.appearance = window.appearance
            window.contentView = host
            host.frame = frame
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("curfew-\(name).png"))
        }
    }
#endif
