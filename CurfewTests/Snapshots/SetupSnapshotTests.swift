#if DEBUG
    import AppKit
    @testable import Curfew
    import CurfewKit
    import SwiftUI
    import XCTest

    /// Setup steps for `just snapshot`: each step in light and dark, plus the
    /// floating drag panel and the lock preview.
    extension DestinationSnapshotTests {
        func testRenderSetupSteps() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            model.settings.hasCompletedInitialSetup = false
            // Show the sign-in offer a fresh install sees.
            model.settings.accountSync.enrollment = nil
            let size = GettingStartedLayout.windowSize

            for (name, flow) in Self.setupFlows() {
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    let suffix = appearance == .darkAqua ? "dark" : "light"
                    try renderHosted(
                        GettingStartedView(
                            flow: flow,
                            notifications: FixedNotificationPermission(value: .notAsked),
                            makeAccount: {
                                // Never the real Keychain: a fresh, signed-out account.
                                AccountEnrollmentController(
                                    secretStore: EnrollmentRecoveryMemorySecretStore()
                                )
                            }
                        ).environment(model),
                        named: "setup-\(name)-\(suffix)",
                        width: size.width,
                        height: size.height,
                        settlingTime: 0.3,
                        appearance: appearance,
                        to: directory
                    )
                }
            }

            try renderSetupFloatingSurfaces(model: model, to: directory)
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
            let schedule = FirstRunFlow()
            var permissions = schedule
            permissions.chooseSchedule(.weeklySchedule)
            var ready = permissions
            ready.updateAccessibilityGranted(true)
            ready.markCommitted()
            var extras = ready
            extras.advance()
            return [
                ("1-schedule", schedule),
                ("2-permissions", permissions),
                ("3-ready", ready),
                ("4-extras", extras)
            ]
        }
    }
#endif
