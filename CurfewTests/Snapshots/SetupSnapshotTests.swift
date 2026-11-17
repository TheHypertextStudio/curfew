#if DEBUG
    import AppKit
    @testable import Curfew
    import CurfewKit
    import SwiftUI
    import XCTest

    /// Setup screens for `just snapshot`: every screen, plus the floating drag
    /// panel and the lock preview.
    extension DestinationSnapshotTests {
        func testRenderSetupSteps() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            model.settings.hasCompletedInitialSetup = false
            // Show the sign-in offer a fresh install sees.
            model.settings.accountSync.enrollment = nil
            let size = GettingStartedLayout.windowSize

            // Setup is drawn over its own sky, so it looks the same in light and dark.
            for (name, flow) in Self.setupFlows() {
                try renderHosted(
                    setupView(flow: flow).environment(model),
                    named: "setup-\(name)", width: size.width, height: size.height,
                    settlingTime: 0.3, to: directory
                )
            }
            var question = FirstRunFlow()
            question.begin()
            try renderHosted(
                setupView(flow: question, editingMorning: true).environment(model),
                named: "setup-2b-morning", width: size.width, height: size.height,
                settlingTime: 0.3, to: directory
            )

            try renderSetupFloatingSurfaces(model: model, to: directory)
        }

        private func setupView(flow: FirstRunFlow, editingMorning: Bool = false) -> some View {
            GettingStartedView(
                flow: flow,
                editingMorning: editingMorning,
                notifications: FixedNotificationPermission(value: .notAsked),
                makeAccount: {
                    // Never the real Keychain: a fresh, signed-out account.
                    AccountEnrollmentController(
                        secretStore: EnrollmentRecoveryMemorySecretStore()
                    )
                }
            )
        }

        private func renderSetupFloatingSurfaces(
            model: CurfewAppModel,
            to directory: URL
        ) throws {
            let bundleURL = Bundle.main.bundleURL
            try renderHosted(
                GettingStartedDragPanelView(
                    icon: NSWorkspace.shared.icon(forFile: bundleURL.path),
                    bundleURL: bundleURL
                ),
                named: "setup-drag-panel",
                width: DragPanelPlacement.panelSize.width,
                height: DragPanelPlacement.panelSize.height,
                to: directory
            )

            let preview = model.lockPreviewContent(now: model.currentTime, usesWeeklySchedule: true)
            try renderHosted(
                GettingStartedLockPreviewView(
                    content: preview,
                    appearance: model.restAppearance,
                    onEnd: {}
                ),
                named: "setup-lock-preview",
                width: 1280,
                height: 800,
                settlingTime: 0.3,
                to: directory
            )
        }

        static func setupFlows() -> [(String, FirstRunFlow)] {
            let welcome = FirstRunFlow()
            var schedule = welcome
            schedule.begin()
            var permissions = schedule
            permissions.chooseSchedule(.weeklySchedule)
            var optional = permissions
            optional.updateAccessibilityGranted(true)
            optional.markCommitted(offersOptional: true)
            var ready = optional
            ready.advance()
            var extras = ready
            extras.advance()
            return [
                ("1-welcome", welcome),
                ("2-schedule", schedule),
                ("3-permission", permissions),
                ("4-optional", optional),
                ("5-ready", ready),
                ("6-extras", extras)
            ]
        }
    }
#endif
