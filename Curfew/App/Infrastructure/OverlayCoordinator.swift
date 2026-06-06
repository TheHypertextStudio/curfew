import AppKit
import SwiftUI

/// Value type that captures the window-level properties applied to all
/// overlay windows of a given kind. Centralising these in a struct means
/// the warning, lockout, and timer windows can each be described in one
/// place and reused for both initial creation and frame-update paths.
struct OverlayWindowConfiguration: Equatable {
    /// Window style flags — overlays use `.borderless` so no title bar appears.
    var styleMask: NSWindow.StyleMask

    /// Drawing priority. `.floating` for warnings, `.screenSaver` for lockout
    /// (above the dock and full-screen apps), `.statusBar` for the timer pill.
    var level: NSWindow.Level

    /// When `true` the window is transparent to mouse input. Warning and timer
    /// windows pass through clicks; the lockout window captures them.
    var ignoresMouseEvents: Bool

    /// Ensures the overlay appears on all Spaces and in full-screen mode.
    var collectionBehavior: NSWindow.CollectionBehavior

    /// Always `false` for overlays — they must stay full-screen.
    var isMovable: Bool

    /// Always `false` — overlays must not vanish when another app is focused.
    var hidesOnDeactivate: Bool
}

/// Manages the set of overlay `NSWindow` instances that visualise
/// ``CurfewEvaluation`` across every connected display.
///
/// One window per screen per overlay kind (warning / lockout / timer) keeps
/// multi-monitor setups consistent. The coordinator creates windows lazily on
/// first need, updates them in-place on subsequent ticks, and tears them down
/// when the phase clears. `CurfewAppModel` calls
/// ``updateOverlays(for:model:lockoutMessage:)`` once per tick.
@MainActor
final class OverlayCoordinator {
    /// Window configuration for the translucent dim overlay shown during the
    /// warning phase. Mouse events pass through so normal interaction continues.
    static let warningWindowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless],
        level: .floating,
        ignoresMouseEvents: true,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )

    /// Window configuration for the full-screen lockout overlay. Level
    /// `.screenSaver` keeps it above the Dock and any full-screen app.
    /// Mouse events are captured so the user cannot interact with the desktop.
    static let lockoutWindowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless],
        level: .screenSaver,
        ignoresMouseEvents: false,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )

    /// Window configuration for the small floating countdown timer shown at
    /// T-5 and below. Level `.statusBar` keeps it above normal windows but
    /// below the lockout overlay. Mouse events pass through.
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

    /// Reconciles the visible overlay windows with `state`. Called once per
    /// tick; creates, updates, or removes windows as needed. Hides irrelevant
    /// window kinds first to avoid z-order flicker.
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

    /// Brings every live lockout window back to the front of the z-order
    /// without rebuilding it. Used when the user returns to the Mac (app
    /// activation / system wake): another app or the wake transition can leave
    /// a lockout overlay behind a newly-focused window even though our window
    /// level is `.screenSaver`. Re-ordering front restores the cover.
    ///
    /// No-ops when no lockout windows exist (i.e. not in a locked phase), so it
    /// is safe to call on every activation regardless of the current phase.
    func reassertLockoutFrontmost() {
        for window in lockoutWindows.values {
            window.orderFrontRegardless()
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

/// Translucent fill shown during the warning phase. Opacity ramps with
/// the warning stage (see `WarningStage.overlayOpacity`) so the dim
/// deepens as the lock approaches.
private struct WarningOverlayView: View {
    /// 0.0–1.0 opacity for the tint. `0` hides the overlay entirely.
    let opacity: Double
    /// Respects the system "Reduce transparency" accessibility setting by
    /// switching to a solid black fill at a slightly bumped alpha. Matches
    /// the handling in `CurfewTheme`.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// SwiftUI body — solid or tinted fill ignoring safe area so the
    /// overlay covers the menu bar and Dock zones too.
    var body: some View {
        let base = reduceTransparency
            ? Color.black.opacity(min(0.9, max(0.2, opacity + 0.30)))
            : CurfewTheme.warning.opacity(opacity)

        base
            .ignoresSafeArea()
    }
}

/// Small pill-shaped countdown shown in the top-right corner of each
/// screen during the last few minutes before lockout. Non-interactive
/// (window passes clicks through) — purely informative.
private struct FloatingCountdownTimerView: View {
    /// Whole minutes until lockout. Clamped to `>= 0` so the view
    /// never displays a negative number if the tick loop hands it
    /// a stale or just-over value.
    let minutesRemaining: Int

    /// SwiftUI body — monospace digit capsule with a subtle border.
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
