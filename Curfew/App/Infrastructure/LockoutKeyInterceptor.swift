import ApplicationServices
import CoreGraphics
import CurfewKit
import Foundation

/// Pure-function policy for deciding whether a key event should be blocked
/// while Curfew is in lockout.
///
/// Kept separate from the interceptor class so it is trivially testable: we
/// feed raw key codes + modifier flags in, get "block / allow" out, with no
/// CoreGraphics tap or run loop involvement. The interceptor calls this for
/// every candidate event.
///
/// The blocklist is deliberately small — enough to deter the obvious bypass
/// attempts (⌘⇥ to switch apps, ⌘Q to quit, ⌘Space to spotlight, ⌘⌥Esc for
/// force quit, Ctrl+arrows for Mission Control spaces) without reinventing a
/// kiosk-mode keyboard driver. The privileged helper preserves deadline and
/// shutdown enforcement but intentionally does not inject system-wide input.
enum LockoutShortcutPolicy {
    /// Returns `true` iff the given key + modifier combination should be
    /// swallowed while lockout is active.
    ///
    /// Key codes are the standard macOS virtual key codes (see `Events.h`):
    /// 48 = tab, 12 = q, 49 = space, 53 = escape, 123–126 = arrow keys,
    /// 13 = w, 4 = h, 46 = m, 50 = backtick, 131 = F4 (Launchpad), 160 =
    /// F3 (Mission Control), 103 = F11, 111 = F12.
    static func shouldBlock(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        let command = flags.contains(.maskCommand)
        let option = flags.contains(.maskAlternate)
        let control = flags.contains(.maskControl)

        // Cmd-modified bypass shortcuts.
        if command {
            // ⌘⇥ app switcher, ⌘Q quit, ⌘W close window, ⌘H hide, ⌘M minimize,
            // ⌘Space spotlight, ⌘` cycle windows of same app. All of these
            // either move focus away from the lockout overlay or dismiss
            // its host window outright.
            if [48, 12, 13, 4, 46, 49, 50].contains(keyCode) {
                return true
            }
        }
        // ⌘⌥Esc force-quit dialog.
        if command, option, keyCode == 53 {
            return true
        }
        // Ctrl-arrows for Spaces navigation.
        if control, [123, 124, 125, 126].contains(keyCode) {
            return true
        }
        // F3 Mission Control, F4 Launchpad, F11 show desktop, F12 dashboard —
        // all desktop-pivot affordances that surface non-Curfew windows.
        if [131, 160, 103, 111].contains(keyCode) {
            return true
        }
        return false
    }
}

/// Mutable heap box holding the live tap port, handed to the C event-tap
/// callback through its `userInfo` pointer.
///
/// The `CGEventTapCallBack` is a C function pointer and therefore cannot
/// capture `self`. To let the callback re-enable a tap the OS just disabled,
/// we pass a retained pointer to this box as `userInfo`; the callback reads
/// ``tap`` back out via `Unmanaged`. The field is filled in *after*
/// `CGEvent.tapCreate` returns (the port doesn't exist until then), so the
/// callback always sees the current port for the lifetime of the tap.
private final class TapPortBox {
    /// The live CGEvent tap port, set immediately after creation.
    var tap: CFMachPort?
}

/// Installs a `CGEventTap` at the session level that consults
/// `LockoutShortcutPolicy` for every keydown while lockout is active.
///
/// Requires the host app to hold the Accessibility entitlement; without it
/// `CGEvent.tapCreate` will succeed at install time but the tap will be
/// disabled by the OS at first event. The getting-started flow walks the
/// user through granting this permission in System Settings.
///
/// The tap is kept resilient: the OS can disable a tap that is too slow to
/// respond (`tapDisabledByTimeout`) or after certain user input
/// (`tapDisabledByUserInput`), and a tap can vanish entirely. The callback
/// re-enables itself on the disable events, and a 2-second watchdog
/// (``TapWatchdogDecision``) re-enables a disabled tap or recreates a vanished
/// one so a silently downed shield self-heals.
///
/// This is a best-effort input deterrent — a determined user with root access
/// can still bypass it. The privileged helper adds a separate higher-privilege
/// deadline and shutdown layer rather than pretending to be a keyboard driver.
final class LockoutKeyInterceptor {
    /// Remediation the watchdog should take for a tap given its observable
    /// state. Pure and `Equatable` so the decision is unit-testable without a
    /// live tap or run loop.
    enum TapWatchdogDecision: Equatable {
        /// The tap is installed and OS-enabled; nothing to do.
        case healthy
        /// The tap is installed but the OS disabled it; re-enable it in place.
        case reEnable
        /// The tap is no longer installed; recreate it from scratch.
        case recreate

        /// Maps a tap's observable facts to the watchdog's remediation.
        ///
        /// - Parameters:
        ///   - installed: Whether the tap port still exists
        ///     (``LockoutKeyInterceptor/isActive``).
        ///   - enabled: Whether the OS reports the tap as enabled and firing
        ///     (``LockoutKeyInterceptor/isEnabled``). Ignored when not
        ///     `installed`, since a vanished tap must be recreated regardless.
        /// - Returns: ``recreate`` when the tap is gone, ``reEnable`` when it is
        ///   installed but disabled, otherwise ``healthy``.
        static func decide(installed: Bool, enabled: Bool) -> TapWatchdogDecision {
            if !installed {
                .recreate
            } else if !enabled {
                .reEnable
            } else {
                .healthy
            }
        }
    }

    /// The live CGEvent tap port, or `nil` when stopped.
    private var eventTap: CFMachPort?

    /// Main run-loop source wrapping `eventTap`, or `nil` when stopped.
    private var source: CFRunLoopSource?

    /// Retained box shared with the C callback so it can re-enable the tap on
    /// disable events. Released in ``stop()``.
    private var portBox: Unmanaged<TapPortBox>?

    /// Periodic timer that re-enables a disabled tap or recreates a vanished
    /// one. `nil` when stopped.
    private var watchdog: Timer?

    /// How often the watchdog re-checks the tap, in seconds.
    private static let watchdogInterval: TimeInterval = 2

    /// Whether the tap is currently *installed* on the main run loop
    /// (`eventTap != nil`). Installed does not imply firing — the OS may have
    /// disabled it; see ``isEnabled``.
    var isActive: Bool {
        eventTap != nil
    }

    /// Whether the tap is currently *OS-enabled and firing*
    /// (`CGEvent.tapIsEnabled`). `false` when the tap is uninstalled or when
    /// the OS has disabled it (timeout, user input). A tap can be ``isActive``
    /// yet not `isEnabled`; the watchdog exists to close that gap.
    var isEnabled: Bool {
        eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    /// Installs the event tap and starts the watchdog. Safe to call
    /// repeatedly; no-ops when already running. If the tap fails to create
    /// (e.g. accessibility not granted), this silently returns without setting
    /// `eventTap` — callers should check ``isActive`` if they need to know
    /// whether interception took.
    ///
    /// `start()` is invoked every tick (1 Hz) while locked, so when the tap
    /// cannot install it would otherwise spin up a fresh `Timer` each second.
    /// The watchdog is therefore (re)started only when none is already
    /// scheduled; an existing watchdog's ``TapWatchdogDecision/recreate`` path
    /// already retries the install on its own cadence.
    func start() {
        // Skip in a unit-test host: creating the CGEvent tap raises the macOS
        // Accessibility ("control your computer") prompt, and every re-signed
        // test build re-prompts. No test asserts the live tap; production
        // launches install it as normal.
        guard !RuntimeEnvironment.isUnitTestHost else { return }
        guard eventTap == nil else {
            return
        }

        installTap()
        if watchdog == nil {
            startWatchdog()
        }
    }

    /// Removes the event tap from the main run loop and stops the watchdog.
    /// Safe to call when not started. Idempotent.
    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        uninstallTap()
    }

    /// Self-cleaning teardown: invalidates the watchdog, uninstalls the tap, and
    /// releases the ``TapPortBox`` if the instance is deallocated without an
    /// explicit ``stop()``. Leans on `stop()`'s idempotence.
    deinit {
        stop()
    }

    // MARK: - Tap lifecycle

    /// Creates the session tap, adds it to the main run loop, enables it, and
    /// wires up the callback's port box. No-ops if creation fails.
    private func installTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let box = TapPortBox()
        let boxPointer = Unmanaged.passRetained(box)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: Self.eventCallback,
                userInfo: boxPointer.toOpaque()
            )
        else {
            boxPointer.release()
            return
        }

        box.tap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        source = runLoopSource
        portBox = boxPointer
    }

    /// Tears down the tap and releases the callback's port box. Idempotent.
    private func uninstallTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        portBox?.release()

        eventTap = nil
        source = nil
        portBox = nil
    }

    /// The C event-tap callback. Re-enables the tap on OS disable events, then
    /// applies the lockout blocklist to key events. Cannot capture `self`, so
    /// it reaches the tap port through the boxed `userInfo` pointer.
    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let userInfo {
                let box = Unmanaged<TapPortBox>.fromOpaque(userInfo).takeUnretainedValue()
                if let tap = box.tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return nil
        }

        guard type == .keyDown || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if LockoutShortcutPolicy.shouldBlock(keyCode: keyCode, flags: flags) {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Watchdog

    /// Starts the periodic watchdog on the main run loop, replacing any prior
    /// timer.
    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(
            timeInterval: Self.watchdogInterval,
            repeats: true
        ) { [weak self] _ in
            self?.runWatchdog()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    /// Consults ``TapWatchdogDecision`` and acts: re-enables a disabled tap or
    /// reinstalls a vanished one.
    private func runWatchdog() {
        switch TapWatchdogDecision.decide(installed: isActive, enabled: isEnabled) {
        case .healthy:
            break
        case .reEnable:
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .recreate:
            uninstallTap()
            installTap()
        }
    }
}
