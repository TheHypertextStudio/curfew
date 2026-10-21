import AppKit
import CurfewKit
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

    /// Window configuration for the full-screen morning (sunrise) reflection
    /// overlay. Same commanding `.screenSaver` presence as the lockout so it
    /// owns the screen the moment it appears, but it is *not* paired with the
    /// key interceptor — the user can dismiss it (Start / Skip) at any time.
    static let daybreakWindowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless],
        level: .screenSaver,
        ignoresMouseEvents: false,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )

    /// Whether this process must not put overlay windows on screen.
    ///
    /// True in a unit-test host, and false everywhere else — including the
    /// Debug demo-capture launch, which exists precisely to photograph these
    /// windows and opts in explicitly through `CURFEW_DEMO_FIXTURE=1`. The
    /// exemption cannot weaken the unit suite (which sets no such variable)
    /// or a Release build (where the demo machinery is not compiled).
    static var suppressesWindows: Bool {
        guard RuntimeEnvironment.isUnitTestHost else { return false }
        #if DEBUG
            return CurfewLaunchBehavior.demoScenario(
                environment: ProcessInfo.processInfo.environment
            ) == nil
        #else
            return true
        #endif
    }

    private var warningWindows: [ObjectIdentifier: NSWindow] = [:]
    private let lockoutWindows = RestWindowStore()
    private var timerWindows: [ObjectIdentifier: NSWindow] = [:]
    private var restDisplayStates: [CGDirectDisplayID: RestDisplayPresentation] = [:]
    private var restLifecycle = RestDisplayLifecycle()
    private var restIsSleeping = false
    private var restSessionIsActive = true
    private lazy var restVisibilityObserver = RestWindowVisibilityObserver { [weak self] in
        self?.reconcileRestVisibility()
    }

    var restCanReveal: Bool {
        !restIsSleeping && restSessionIsActive
    }

    func restSessionResigned() {
        restSessionIsActive = false
        restDisplaysHidden()
    }

    func restSessionActivated() {
        restSessionIsActive = true
        restDisplaysWoke()
    }

    /// Reconciles the visible overlay windows with `state`. Called once per
    /// tick; creates, updates, or removes windows as needed. Hides irrelevant
    ///
    /// Guarded by ``suppressesWindows`` for the same reason as
    /// ``LockoutKeyInterceptor`` — its paired half — and every other side
    /// effect in the tick loop. Without it, any test that ticks a model into
    /// `.locked` throws a real `.screenSaver`-level window over whoever is
    /// running the suite, and the interceptor's own guard means the keyboard
    /// still works while the screen is covered. Tests that need to assert on
    /// overlay behaviour read the static `*WindowConfiguration` values, which
    /// this guard leaves untouched.
    func updateOverlays(
        for state: CurfewEvaluation,
        model: CurfewAppModel,
        lockoutMessage: String
    ) {
        guard !Self.suppressesWindows else { return }
        if model.shouldPresentRestScreen {
            hideWarningWindows()
            hideTimerWindows()
            showLockoutWindows(model: model, message: lockoutMessage)
        } else {
            hideLockoutWindows()
            if state.phase == .warning {
                showWarningWindows(opacity: state.warningStage.overlayOpacity)
                if state.warningStage.showsFloatingTimer {
                    showTimerWindows(minutesRemaining: state.minutesRemaining)
                } else {
                    hideTimerWindows()
                }
            } else {
                hideWarningWindows()
                hideTimerWindows()
            }
        }
    }

    /// Uses the retained rest hosts for the morning reflection as well.
    func syncDaybreakOverlay(presented: Bool, model: CurfewAppModel) {
        guard !Self.suppressesWindows else { return }
        if presented || model.isEnforcingLockout {
            showLockoutWindows(model: model, message: model.lockoutMessage)
        } else {
            hideLockoutWindows()
        }
    }

    /// Restore the retained covering windows without replacing their content.
    func reassertLockoutFrontmost() {
        for window in lockoutWindows.windows.values {
            window.orderFrontRegardless()
        }
    }

    func restDisplaysHidden() {
        restIsSleeping = true
        for (id, presentation) in restDisplayStates {
            _ = restLifecycle.handle(.hidden, for: id)
            presentation.isVisible = false
        }
    }

    func restDisplaysWoke() {
        restIsSleeping = false
        for id in restDisplayStates.keys {
            _ = restLifecycle.handle(.wakeObserved, for: id)
        }
        reconcileRestVisibility()
    }

    func reconcileRestVisibility() {
        guard restCanReveal else { return }
        for (id, window) in lockoutWindows.windows {
            let awake = CGDisplayIsAsleep(id) == 0
            guard !awake || window.occlusionState.contains(.visible) else { continue }
            if restLifecycle.observeVisibleDisplay(isAwake: awake, for: id) == .begin {
                restDisplayStates[id]?.revealGeneration += 1
            }
            restDisplayStates[id]?.isVisible = restLifecycle.isVisible(for: id)
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

    private func showLockoutWindows(model: CurfewAppModel, message _: String) {
        let displays = RestDisplay.connected
        let connected = Set(displays.map(\.id))
        for id in restDisplayStates.keys where !connected.contains(id) {
            restDisplayStates.removeValue(forKey: id)
            _ = restLifecycle.handle(.removed, for: id)
        }
        lockoutWindows.reconcile(displays: displays) { display in
            let window = Self.makeDaybreakWindow(frame: display.frame, screen: nil)
            window.delegate = restVisibilityObserver
            apply(configuration: Self.lockoutWindowConfiguration, to: window)
            let presentation = restDisplayStates[display.id] ?? RestDisplayPresentation()
            restDisplayStates[display.id] = presentation
            _ = restLifecycle.handle(.hidden, for: display.id)
            presentation.isVisible = false
            window.contentView = Self.makeRestHostingView(
                rootView: RestScreenView(model: model, display: presentation)
            )
            return window
        }
        for window in lockoutWindows.windows.values where !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        reconcileRestVisibility()
    }

    private func hideWarningWindows() {
        for window in warningWindows.values {
            window.orderOut(nil)
        }
        warningWindows.removeAll()
    }

    private func hideLockoutWindows() {
        lockoutWindows.removeAll()
        restDisplayStates.removeAll()
        restLifecycle = RestDisplayLifecycle()
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

    func apply(configuration: OverlayWindowConfiguration, to window: NSWindow) {
        let coversScreen = configuration.level == .screenSaver
        window.isOpaque = coversScreen
        window.backgroundColor = coversScreen ? .black : .clear
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

    /// SwiftUI body — a small dusk capsule with the minutes remaining.
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SundownPalette.glow)
            Text("\(max(0, minutesRemaining)) min")
                .accessibilityIdentifier("warning-countdown")
                .accessibilityLabel("\(max(0, minutesRemaining)) min")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SundownPalette.warmWhite)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SundownPalette.nightSky, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("warning-timer")
    }
}
