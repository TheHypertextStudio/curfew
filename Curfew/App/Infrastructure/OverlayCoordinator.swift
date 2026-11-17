import AppKit
import CurfewKit
import SwiftUI

/// Value type that captures the window-level properties applied to all
/// overlay windows of a given kind. Centralising these in a struct means
/// the warning and lockout windows can each be described in one
/// place and reused for both initial creation and frame-update paths.
struct OverlayWindowConfiguration: Equatable {
    /// Window style flags — overlays use `.borderless` so no title bar appears.
    var styleMask: NSWindow.StyleMask

    /// Drawing priority. Warning and lockout windows must both appear above
    /// full-screen apps; input policy differs between the two phases.
    var level: NSWindow.Level

    /// When `true` the window is transparent to mouse input. Warning
    /// windows pass through clicks; the lockout window captures them.
    var ignoresMouseEvents: Bool

    /// Ensures the overlay appears on all Spaces and in full-screen mode.
    var collectionBehavior: NSWindow.CollectionBehavior

    /// Always `false` for overlays — they must stay full-screen.
    var isMovable: Bool

    /// Always `false` — overlays must not vanish when another app is focused.
    var hidesOnDeactivate: Bool

    /// Always `false` — overlays must not vanish when Curfew is hidden.
    var canHide = false
}

/// Manages the set of overlay `NSWindow` instances that visualise
/// ``CurfewEvaluation`` across every connected display.
///
/// One window per screen per overlay kind (warning / lockout) keeps
/// multi-monitor setups consistent. The coordinator creates windows lazily on
/// first need, updates them in-place on subsequent ticks, and tears them down
/// when the phase clears. `CurfewAppModel` calls
/// ``updateOverlays(for:model:)`` once per tick.
@MainActor
final class OverlayCoordinator {
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
    private let warningTint = WarningTintState()
    private let lockoutWindows = RestWindowStore()
    private let noticeCoordinator = WarningNoticeCoordinator()
    /// The scene every lock window shares, from the lock's first window until
    /// its windows have faded away.
    private var lockScene: LockScene?
    private var restDisplayStates: [CGDirectDisplayID: RestDisplayPresentation] = [:]
    private var restLifecycle = RestDisplayLifecycle()
    private var restIsSleeping = false
    private var restSessionIsActive = true
    private lazy var restVisibilityObserver = RestWindowVisibilityObserver { [weak self] in
        self?.reconcileRestVisibility()
    }

    private weak var lockoutModel: CurfewAppModel?
    private lazy var lockoutFocus = LockoutFocusController(
        holdsFocus: { [weak self] in self?.lockoutModel?.restHandoffIsAmbient == false },
        onScreensChanged: { [weak self] in
            guard let self, let model = lockoutModel, !lockoutWindows.windows.isEmpty else {
                return
            }
            showLockoutWindows(model: model)
        }
    )

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
    func updateOverlays(for state: CurfewEvaluation, model: CurfewAppModel) {
        guard !Self.suppressesWindows else { return }
        if model.shouldPresentRestScreen {
            hideWarningWindows()
            noticeCoordinator.reset()
            showLockoutWindows(model: model)
        } else {
            hideLockoutWindows()
            switch state.phase {
            case .warning:
                showWarningWindows(opacity: state.warningStage.overlayOpacity)
                noticeCoordinator.update(
                    stage: state.warningStage,
                    curfew: state.lockDate,
                    minutesRemaining: state.minutesRemaining
                )
            default:
                noticeCoordinator.reset()
                hideWarningWindows()
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
        lockoutFocus.reassert()
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

        warningTint.opacity = opacity
        let screens = NSScreen.screens
        let connected = Set(screens.map(ObjectIdentifier.init))
        for key in warningWindows.keys where !connected.contains(key) {
            warningWindows.removeValue(forKey: key)?.orderOut(nil)
        }
        for screen in screens {
            let key = ObjectIdentifier(screen)
            if let window = warningWindows[key] {
                if window.frame != screen.frame {
                    window.setFrame(screen.frame, display: true)
                }
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
            window.contentView = NSHostingView(rootView: WarningOverlayView(tint: warningTint))
            window.orderFrontRegardless()
            warningWindows[key] = window
        }
    }

    private func showLockoutWindows(model: CurfewAppModel, message _: String = "") {
        let scene = currentLockScene(model: model)
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
            window.contentView = Self.makeRestContentView(
                model: model, display: presentation, scene: scene
            )
            return window
        }
        for window in lockoutWindows.windows.values where !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        lockoutModel = model
        // Demo captures and the dismissible morning screen keep normal focus.
        if model.isEnforcingLockout, !model.isDemoSession {
            lockoutFocus.engage()
        } else {
            lockoutFocus.release()
        }
        reconcileRestVisibility()
    }

    private func hideWarningWindows() {
        for window in warningWindows.values {
            window.orderOut(nil)
        }
        warningWindows.removeAll()
    }

    /// The lock's shared scene. A new lock starts from the sky the person was
    /// looking at; a morning-only screen or a relaunch mid-lock is settled.
    private func currentLockScene(model: CurfewAppModel) -> LockScene {
        if let lockScene {
            lockScene.relock()
            return lockScene
        }
        let scene = LockScene()
        let now = model.currentTime
        if model.isEnforcingLockout {
            scene.begin(at: now, startingFrame: model.horizonFrame)
        } else {
            scene.settle(at: now)
        }
        lockScene = scene
        return scene
    }

    /// Release fades the scene to the desktop before the windows go, in a
    /// short fade under Reduce Motion. Focus and input return at once.
    private func hideLockoutWindows() {
        lockoutFocus.release()
        lockoutModel = nil
        if let lockScene, !lockoutWindows.windows.isEmpty {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            lockScene.release(at: Date(), reduceMotion: reduceMotion)
            lockoutWindows.leave(
                duration: LockSceneTimeline.leavingDuration(reduceMotion: reduceMotion)
            )
        } else {
            lockoutWindows.removeAll()
        }
        lockScene = nil
        restDisplayStates.removeAll()
        restLifecycle = RestDisplayLifecycle()
    }

    func apply(configuration: OverlayWindowConfiguration, to window: NSWindow) {
        let coversScreen = !configuration.ignoresMouseEvents
        window.setAccessibilityModal(coversScreen)
        window.isOpaque = coversScreen
        window.backgroundColor = coversScreen ? .black : .clear
        if coversScreen {
            window.appearance = NSAppearance(named: .darkAqua)
        }
        window.hasShadow = false
        window.level = configuration.level
        window.ignoresMouseEvents = configuration.ignoresMouseEvents
        window.collectionBehavior = configuration.collectionBehavior
        window.isMovable = configuration.isMovable
        window.hidesOnDeactivate = configuration.hidesOnDeactivate
        window.canHide = configuration.canHide
    }
}

/// The warning tint's opacity, observed by windows that are built once.
@Observable
@MainActor
final class WarningTintState {
    var opacity = 0.0
}

/// Translucent fill shown during the warning phase. Opacity ramps with
/// the warning stage (see `WarningStage.overlayOpacity`) so the dim
/// deepens as the lock approaches.
private struct WarningOverlayView: View {
    let tint: WarningTintState

    private var opacity: Double {
        tint.opacity
    }

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
