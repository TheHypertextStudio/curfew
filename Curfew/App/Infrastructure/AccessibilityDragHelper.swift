import AppKit
import CoreGraphics
import Foundation

/// Finds the frame of the frontmost System Settings window.
@MainActor
protocol SystemSettingsWindowLocating {
    /// The window's frame in AppKit global coordinates, or `nil` when no
    /// System Settings window is on screen.
    func systemSettingsWindowFrame() -> CGRect?
}

/// Shows and moves the floating drag panel. Abstracted so the helper's
/// logic is tested without creating windows.
@MainActor
protocol DragPanelPresenting: AnyObject {
    func show(at frame: CGRect)
    func move(to frame: CGRect)
    func hide()
}

/// Where the drag panel goes. Pure geometry in AppKit global coordinates
/// (origin at the bottom left of the primary display).
enum DragPanelPlacement {
    static let panelSize = CGSize(width: 232, height: 180)
    /// Space between System Settings and the panel.
    static let gap: CGFloat = 16
    /// Distance from a screen edge when the panel falls back to a corner.
    static let margin: CGFloat = 24
    /// How far below the window's top edge the panel sits, roughly level
    /// with the top of the Accessibility list.
    static let topInset: CGFloat = 96

    static func frame(
        beside window: CGRect?,
        screens: [CGRect],
        size: CGSize = panelSize
    ) -> CGRect {
        guard let screen = screens.first else {
            return CGRect(origin: .zero, size: size)
        }
        guard let window else {
            return CGRect(
                x: screen.maxX - size.width - margin,
                y: screen.maxY - size.height - margin,
                width: size.width,
                height: size.height
            )
        }
        let home = screens.max {
            $0.intersection(window).area < $1.intersection(window).area
        } ?? screen
        let top = min(
            max(window.maxY - topInset - size.height, home.minY + 8),
            home.maxY - size.height - 8
        )
        let right = window.maxX + gap
        if right + size.width <= home.maxX - 8 {
            return CGRect(x: right, y: top, width: size.width, height: size.height)
        }
        let left = window.minX - gap - size.width
        if left >= home.minX + 8 {
            return CGRect(x: left, y: top, width: size.width, height: size.height)
        }
        return CGRect(
            x: home.maxX - size.width - margin,
            y: top,
            width: size.width,
            height: size.height
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        isNull ? 0 : width * height
    }
}

/// Reads System Settings' window bounds from the window list. Bounds and
/// owner are available without Screen Recording permission; only titles and
/// contents are withheld, and neither is needed here.
@MainActor
struct SystemSettingsWindowLocator: SystemSettingsWindowLocating {
    static let bundleIdentifier = "com.apple.systempreferences"

    func systemSettingsWindowFrame() -> CGRect? {
        let owners = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier)
                .map(\.processIdentifier)
        )
        guard !owners.isEmpty,
              let list = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]],
              let bounds = Self.settingsWindowBounds(in: list, ownedBy: owners),
              let primary = NSScreen.screens.first
        else { return nil }
        return Self.appKitFrame(
            fromWindowListBounds: bounds,
            primaryScreenHeight: primary.frame.height
        )
    }

    /// The frontmost normal-layer window owned by System Settings. The list
    /// is ordered front to back.
    nonisolated static func settingsWindowBounds(
        in windows: [[String: Any]],
        ownedBy owners: Set<pid_t>
    ) -> CGRect? {
        for info in windows {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                ?? info[kCGWindowOwnerPID as String] as? Int32,
                owners.contains(pid),
                (info[kCGWindowLayer as String] as? Int) == 0,
                let raw = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = rect(from: raw),
                bounds.width >= 200, bounds.height >= 200
            else { continue }
            return bounds
        }
        return nil
    }

    /// Window list bounds have their origin at the top left of the primary
    /// display; AppKit's is at the bottom left.
    nonisolated static func appKitFrame(
        fromWindowListBounds bounds: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: bounds.minX,
            y: primaryScreenHeight - bounds.minY - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    private nonisolated static func rect(from raw: [String: Any]) -> CGRect? {
        func number(_ key: String) -> CGFloat? {
            (raw[key] as? NSNumber).map { CGFloat($0.doubleValue) }
        }
        guard let originX = number("X"), let originY = number("Y"),
              let width = number("Width"), let height = number("Height") else { return nil }
        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}

/// Step 2's helper: opens the Accessibility pane, keeps a small panel with
/// the app icon beside System Settings while it moves, and tells setup the
/// moment trust is granted.
///
/// It never fires the system Accessibility prompt: the panel's drag adds
/// Curfew to the list, so the pane and a prompt never compete for attention.
@MainActor
final class AccessibilityDragHelper {
    /// Called once, when trust goes from missing to granted.
    var onGranted: (() -> Void)?

    private let isTrusted: () -> Bool
    private let windows: any SystemSettingsWindowLocating
    private let screens: () -> [CGRect]
    private let presenter: any DragPanelPresenting
    private let openPane: () -> Void
    private var wasTrusted: Bool
    private var panelFrame: CGRect?
    private var timer: Timer?

    private(set) var isShowingPanel = false

    init(
        isTrusted: @escaping () -> Bool,
        windows: any SystemSettingsWindowLocating,
        screens: @escaping () -> [CGRect],
        presenter: any DragPanelPresenting,
        openPane: @escaping () -> Void
    ) {
        self.isTrusted = isTrusted
        self.windows = windows
        self.screens = screens
        self.presenter = presenter
        self.openPane = openPane
        self.wasTrusted = isTrusted()
    }

    /// Opens the pane and shows the panel beside it.
    func openSystemSettings() {
        openPane()
        let frame = currentPanelFrame()
        panelFrame = frame
        presenter.show(at: frame)
        isShowingPanel = true
    }

    /// One poll: report a fresh grant, otherwise keep the panel beside the
    /// window.
    func tick() {
        let trusted = isTrusted()
        defer { wasTrusted = trusted }
        if trusted, !wasTrusted {
            hidePanel()
            onGranted?()
            return
        }
        guard isShowingPanel, !trusted else { return }
        let frame = currentPanelFrame()
        if frame != panelFrame {
            panelFrame = frame
            presenter.move(to: frame)
        }
    }

    /// Polls on a timer while step 2 is visible. Fast enough for the panel
    /// to keep up with a dragged window.
    func startPolling(interval: TimeInterval = 0.2) {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hidePanel()
    }

    private func hidePanel() {
        guard isShowingPanel else { return }
        isShowingPanel = false
        panelFrame = nil
        presenter.hide()
    }

    private func currentPanelFrame() -> CGRect {
        DragPanelPlacement.frame(beside: windows.systemSettingsWindowFrame(), screens: screens())
    }
}
