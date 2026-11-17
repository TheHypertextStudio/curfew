import CoreGraphics
@testable import Curfew
import Foundation
import Testing

@MainActor
private final class FakeWindowFrames: SystemSettingsWindowLocating {
    var frame: CGRect?
    private(set) var lookups = 0

    init(_ frame: CGRect?) {
        self.frame = frame
    }

    func systemSettingsWindowFrame() -> CGRect? {
        lookups += 1
        return frame
    }
}

@MainActor
private final class FakePanel: DragPanelPresenting {
    private(set) var frames: [CGRect] = []
    private(set) var isVisible = false
    private(set) var hideCount = 0

    func show(at frame: CGRect) {
        frames.append(frame)
        isVisible = true
    }

    func move(to frame: CGRect) {
        frames.append(frame)
    }

    func hide() {
        hideCount += 1
        isVisible = false
    }
}

@MainActor
struct AccessibilityDragHelperTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let panel = DragPanelPlacement.panelSize

    private func makeHelper(
        trusted: Bool = false,
        window: CGRect?
    ) -> Harness {
        let frames = FakeWindowFrames(window)
        let presenter = FakePanel()
        let trust = TrustBox(trusted)
        let opened = Counter()
        let helper = AccessibilityDragHelper(
            isTrusted: { trust.value },
            windows: frames,
            screens: { [screen] },
            presenter: presenter,
            openPane: { opened.count += 1 }
        )
        return Harness(
            helper: helper,
            frames: frames,
            presenter: presenter,
            trust: trust,
            opened: opened
        )
    }

    @Test("The panel sits to the right of System Settings when there is room")
    func placesBesideWindow() {
        let window = CGRect(x: 200, y: 200, width: 700, height: 560)
        let frame = DragPanelPlacement.frame(beside: window, screens: [screen])
        #expect(frame.minX == window.maxX + DragPanelPlacement.gap)
        #expect(frame.size == panel)
        #expect(screen.contains(frame))
        #expect(frame.maxY <= window.maxY)
    }

    @Test("The panel moves to the left when the right edge has no room")
    func placesLeftWhenRightIsFull() {
        let window = CGRect(x: 700, y: 200, width: 700, height: 560)
        let frame = DragPanelPlacement.frame(beside: window, screens: [screen])
        #expect(frame.maxX == window.minX - DragPanelPlacement.gap)
        #expect(screen.contains(frame))
    }

    @Test("A window too wide for either side keeps the panel on screen over its edge")
    func clampsWhenNeitherSideFits() {
        let window = CGRect(x: 40, y: 100, width: 1380, height: 760)
        let frame = DragPanelPlacement.frame(beside: window, screens: [screen])
        #expect(screen.contains(frame))
    }

    @Test("Without a System Settings window the panel uses the top right of the screen")
    func fallsBackToScreenCorner() {
        let frame = DragPanelPlacement.frame(beside: nil, screens: [screen])
        #expect(frame.maxX == screen.maxX - DragPanelPlacement.margin)
        #expect(frame.maxY == screen.maxY - DragPanelPlacement.margin)
    }

    @Test("Window list bounds convert from top-left to AppKit coordinates")
    func convertsCoordinates() {
        let converted = SystemSettingsWindowLocator.appKitFrame(
            fromWindowListBounds: CGRect(x: 100, y: 50, width: 700, height: 500),
            primaryScreenHeight: 900
        )
        #expect(converted == CGRect(x: 100, y: 350, width: 700, height: 500))
    }

    @Test("Only a normal-layer System Settings window is chosen from the window list")
    func picksSettingsWindow() {
        let infos: [[String: Any]] = [
            [
                "kCGWindowOwnerPID": Int32(10), "kCGWindowLayer": 0,
                "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 800, "Height": 600]
            ],
            [
                "kCGWindowOwnerPID": Int32(42), "kCGWindowLayer": 25,
                "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 300, "Height": 30]
            ],
            [
                "kCGWindowOwnerPID": Int32(42), "kCGWindowLayer": 0,
                "kCGWindowBounds": ["X": 120, "Y": 80, "Width": 715, "Height": 640]
            ]
        ]
        let picked = SystemSettingsWindowLocator.settingsWindowBounds(
            in: infos, ownedBy: [42]
        )
        #expect(picked == CGRect(x: 120, y: 80, width: 715, height: 640))
        #expect(SystemSettingsWindowLocator.settingsWindowBounds(in: infos, ownedBy: []) == nil)
    }

    @Test("Opening the pane shows the panel beside the window and never prompts")
    func openShowsPanel() {
        let window = CGRect(x: 200, y: 200, width: 700, height: 560)
        let harness = makeHelper(window: window)
        let helper = harness.helper
        let presenter = harness.presenter
        let opened = harness.opened

        helper.openSystemSettings()

        #expect(opened.count == 1)
        #expect(presenter.isVisible)
        #expect(presenter.frames.last == DragPanelPlacement.frame(
            beside: window,
            screens: [screen]
        ))
    }

    @Test("The panel follows System Settings as it moves")
    func followsWindow() {
        let harness = makeHelper(
            window: CGRect(x: 200, y: 200, width: 700, height: 560)
        )
        let helper = harness.helper
        let frames = harness.frames
        let presenter = harness.presenter
        helper.openSystemSettings()

        let moved = CGRect(x: 100, y: 120, width: 700, height: 560)
        frames.frame = moved
        helper.tick()

        #expect(presenter.frames.last == DragPanelPlacement.frame(beside: moved, screens: [screen]))
    }

    @Test("When the window cannot be found the panel falls back to a screen position")
    func fallbackWhenWindowMissing() {
        let harness = makeHelper(window: nil)
        let helper = harness.helper
        let presenter = harness.presenter
        helper.openSystemSettings()
        #expect(presenter.frames.last == DragPanelPlacement.frame(beside: nil, screens: [screen]))
    }

    @Test("The panel disappears and setup is told the moment access is granted")
    func advancesOnGrant() {
        let harness = makeHelper(
            window: CGRect(x: 200, y: 200, width: 700, height: 560)
        )
        let helper = harness.helper
        let presenter = harness.presenter
        let trust = harness.trust
        var grants = 0
        helper.onGranted = { grants += 1 }
        helper.openSystemSettings()

        helper.tick()
        #expect(grants == 0)
        #expect(presenter.isVisible)

        trust.value = true
        helper.tick()
        helper.tick()

        #expect(grants == 1)
        #expect(!presenter.isVisible)
    }

    @Test("A grant noticed without the panel still advances setup")
    func grantWithoutPanel() {
        let harness = makeHelper(window: nil)
        let helper = harness.helper
        let presenter = harness.presenter
        let trust = harness.trust
        var grants = 0
        helper.onGranted = { grants += 1 }
        trust.value = true
        helper.tick()
        #expect(grants == 1)
        #expect(presenter.frames.isEmpty)
    }

    @Test("Access that already existed does not count as a new grant")
    func existingTrustIsNotAGrant() {
        let harness = makeHelper(trusted: true, window: nil)
        let helper = harness.helper
        var grants = 0
        helper.onGranted = { grants += 1 }
        helper.tick()
        #expect(grants == 0)
    }

    @Test("Stopping hides the panel")
    func stopHides() {
        let harness = makeHelper(
            window: CGRect(x: 200, y: 200, width: 700, height: 560)
        )
        let helper = harness.helper
        let presenter = harness.presenter
        helper.openSystemSettings()
        helper.stop()
        #expect(!presenter.isVisible)
    }
}

private struct Harness {
    let helper: AccessibilityDragHelper
    let frames: FakeWindowFrames
    let presenter: FakePanel
    let trust: TrustBox
    let opened: Counter
}

private final class TrustBox {
    var value: Bool
    init(_ value: Bool) {
        self.value = value
    }
}

private final class Counter {
    var count = 0
}
