import AppKit
import SwiftUI

struct OverlayWindowConfiguration: Equatable {
    var styleMask: NSWindow.StyleMask
    var level: NSWindow.Level
    var ignoresMouseEvents: Bool
    var collectionBehavior: NSWindow.CollectionBehavior
    var isMovable: Bool
    var hidesOnDeactivate: Bool
}

@MainActor
final class OverlayCoordinator {
    static let warningWindowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless],
        level: .floating,
        ignoresMouseEvents: true,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )

    static let lockoutWindowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless],
        level: .screenSaver,
        ignoresMouseEvents: false,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )

    static let timerWindowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless],
        level: .statusBar,
        ignoresMouseEvents: true,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )

    private var warningWindows: [ObjectIdentifier: NSWindow] = [:]
    private var lockoutWindows: [ObjectIdentifier: NSWindow] = [:]
    private var timerWindows: [ObjectIdentifier: NSWindow] = [:]

    func updateOverlays(
        for state: CurfewEvaluation,
        model: CurfewAppModel,
        lockoutMessage: String
    ) {
        switch state.phase {
        case .locked:
            hideWarningWindows()
            hideTimerWindows()
            showLockoutWindows(model: model, message: lockoutMessage)
        case .warning:
            hideLockoutWindows()
            showWarningWindows(opacity: state.warningStage.overlayOpacity)
            if state.warningStage.showsFloatingTimer {
                showTimerWindows(minutesRemaining: state.minutesRemaining)
            } else {
                hideTimerWindows()
            }
        case .working, .dayOff:
            hideWarningWindows()
            hideLockoutWindows()
            hideTimerWindows()
        }
    }

    private func showWarningWindows(opacity: Double) {
        guard opacity > 0 else {
            hideWarningWindows()
            return
        }

        for screen in NSScreen.screens {
            let key = ObjectIdentifier(screen)
            if let window = warningWindows[key] {
                window.setFrame(screen.frame, display: true)
                window.contentView = NSHostingView(rootView: WarningOverlayView(opacity: opacity))
                window.orderFrontRegardless()
                continue
            }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: Self.warningWindowConfiguration.styleMask,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            apply(configuration: Self.warningWindowConfiguration, to: window)
            window.contentView = NSHostingView(rootView: WarningOverlayView(opacity: opacity))
            window.orderFrontRegardless()
            warningWindows[key] = window
        }
    }

    private func showLockoutWindows(model: CurfewAppModel, message: String) {
        for screen in NSScreen.screens {
            let key = ObjectIdentifier(screen)
            if let window = lockoutWindows[key] {
                window.setFrame(screen.frame, display: true)
                let root = LockoutScreenView(message: message).environmentObject(model)
                window.contentView = NSHostingView(rootView: root)
                window.orderFrontRegardless()
                continue
            }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: Self.lockoutWindowConfiguration.styleMask,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            apply(configuration: Self.lockoutWindowConfiguration, to: window)
            let root = LockoutScreenView(message: message).environmentObject(model)
            window.contentView = NSHostingView(rootView: root)
            window.makeKeyAndOrderFront(nil)
            lockoutWindows[key] = window
        }
    }

    private func hideWarningWindows() {
        for window in warningWindows.values {
            window.orderOut(nil)
        }
        warningWindows.removeAll()
    }

    private func hideLockoutWindows() {
        for window in lockoutWindows.values {
            window.orderOut(nil)
        }
        lockoutWindows.removeAll()
    }

    private func showTimerWindows(minutesRemaining: Int) {
        for screen in NSScreen.screens {
            let key = ObjectIdentifier(screen)
            let frame = timerFrame(for: screen)
            let rootView = FloatingCountdownTimerView(minutesRemaining: minutesRemaining)

            if let window = timerWindows[key] {
                window.setFrame(frame, display: true)
                window.contentView = NSHostingView(rootView: rootView)
                window.orderFrontRegardless()
                continue
            }

            let window = NSWindow(
                contentRect: frame,
                styleMask: Self.timerWindowConfiguration.styleMask,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            apply(configuration: Self.timerWindowConfiguration, to: window)
            window.contentView = NSHostingView(rootView: rootView)
            window.orderFrontRegardless()
            timerWindows[key] = window
        }
    }

    private func hideTimerWindows() {
        for window in timerWindows.values {
            window.orderOut(nil)
        }
        timerWindows.removeAll()
    }

    private func timerFrame(for screen: NSScreen) -> CGRect {
        let width: CGFloat = 140
        let height: CGFloat = 50
        let margin: CGFloat = 20
        let originX = screen.visibleFrame.maxX - width - margin
        let originY = screen.visibleFrame.maxY - height - margin
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private func apply(configuration: OverlayWindowConfiguration, to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = configuration.level
        window.ignoresMouseEvents = configuration.ignoresMouseEvents
        window.collectionBehavior = configuration.collectionBehavior
        window.isMovable = configuration.isMovable
        window.hidesOnDeactivate = configuration.hidesOnDeactivate
    }
}

private struct WarningOverlayView: View {
    let opacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let base = reduceTransparency
            ? Color.black.opacity(min(0.9, max(0.2, opacity + 0.30)))
            : CurfewTheme.warning.opacity(opacity)

        base
            .ignoresSafeArea()
    }
}

private struct FloatingCountdownTimerView: View {
    let minutesRemaining: Int

    var body: some View {
        Text("⏳ \(max(0, minutesRemaining))m")
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(.black.opacity(0.72), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
    }
}
