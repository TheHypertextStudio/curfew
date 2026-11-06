import AppKit
import CurfewKit
import SwiftUI

/// An early warning can be dismissed without silencing the next stage. The
/// final five minutes use a persistent countdown.
struct WarningNoticeVisibility {
    private var dismissedStage: WarningStage?

    func shouldShow(_ stage: WarningStage) -> Bool {
        switch stage {
        case .thirtyMinutes, .fifteenMinutes:
            stage != dismissedStage
        case .none, .fiveMinutes, .twoMinutes, .oneMinute, .lockout:
            false
        }
    }

    mutating func dismiss(_ stage: WarningStage) {
        dismissedStage = stage
    }

    mutating func reset() {
        dismissedStage = nil
    }
}

/// Presents an actionable warning on every display without activating Curfew
/// or stealing focus from the user's current fullscreen task.
@MainActor
final class WarningNoticeCoordinator {
    static let windowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless, .nonactivatingPanel],
        level: .screenSaver,
        ignoresMouseEvents: false,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )

    private var windows: [ObjectIdentifier: NSPanel] = [:]
    private var visibility = WarningNoticeVisibility()

    func update(stage: WarningStage, minutesRemaining: Int) {
        guard visibility.shouldShow(stage) else {
            hide()
            return
        }

        for screen in NSScreen.screens {
            let key = ObjectIdentifier(screen)
            let frame = noticeFrame(for: screen)
            let root = WarningNoticeView(minutesRemaining: minutesRemaining) { [weak self] in
                self?.dismiss(stage: stage)
            }
            if let window = windows[key] {
                window.setFrame(frame, display: true)
                window.contentView = NSHostingView(rootView: root)
                window.orderFrontRegardless()
                continue
            }

            let window = NSPanel(
                contentRect: frame,
                styleMask: Self.windowConfiguration.styleMask,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = Self.windowConfiguration.level
            window.ignoresMouseEvents = Self.windowConfiguration.ignoresMouseEvents
            window.collectionBehavior = Self.windowConfiguration.collectionBehavior
            window.isMovable = Self.windowConfiguration.isMovable
            window.hidesOnDeactivate = Self.windowConfiguration.hidesOnDeactivate
            window.becomesKeyOnlyIfNeeded = true
            window.contentView = NSHostingView(rootView: root)
            window.orderFrontRegardless()
            windows[key] = window
        }
    }

    func reset() {
        visibility.reset()
        hide()
    }

    func hide() {
        for window in windows.values {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    private func dismiss(stage: WarningStage) {
        visibility.dismiss(stage)
        hide()
    }

    private func noticeFrame(for screen: NSScreen) -> CGRect {
        let width: CGFloat = 320
        let height: CGFloat = 110
        let margin: CGFloat = 20
        return CGRect(
            x: screen.visibleFrame.maxX - width - margin,
            y: screen.visibleFrame.maxY - height - margin,
            width: width,
            height: height
        )
    }
}

private struct WarningNoticeView: View {
    let minutesRemaining: Int
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(SundownPalette.glow)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Curfew in \(max(1, minutesRemaining)) min")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(SundownPalette.warmWhite)
                Text("Start wrapping up your work.")
                    .font(.system(size: 13))
                    .foregroundStyle(SundownPalette.supportingText)
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SundownPalette.glow)
                    .accessibilityIdentifier("warning-dismiss")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SundownPalette.nightSky, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(SundownPalette.warmWhite.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("early-warning-notice")
    }
}
