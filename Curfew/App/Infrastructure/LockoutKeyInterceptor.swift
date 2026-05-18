import ApplicationServices
import CoreGraphics
import Foundation

/// Reports whether the host process currently holds the Accessibility
/// trust that `LockoutKeyInterceptor` needs to install its CGEventTap.
///
/// The protocol exists so tests can inject a stub instead of relying on
/// the real `AXIsProcessTrustedWithOptions` call, which depends on
/// system-wide state. Production code uses ``SystemAccessibilityTrust``;
/// tests pass a recording stub via ``CurfewAppModel`` init.
protocol AccessibilityTrustChecking {
    /// `true` when this app is in the system's Accessibility allow-list.
    /// Read on every tick so the UI banner updates within seconds of the
    /// user toggling the permission in System Settings.
    var isProcessTrusted: Bool { get }
}

/// Production conformer that wraps the AX trust API.
///
/// Pass `prompt: true` to the underlying API when the model wants the
/// system to surface its own permission prompt; that's a destructive
/// surface so we leave it `false` here and let the Getting Started flow
/// drive the explicit prompt via `NSWorkspace.open`.
struct SystemAccessibilityTrust: AccessibilityTrustChecking {
    var isProcessTrusted: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

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
/// kiosk-mode keyboard driver. A hardened v0.2 will move this behind the
/// privileged helper and intercept at a lower layer.
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

/// Installs a `CGEventTap` at the session level that consults
/// `LockoutShortcutPolicy` for every keydown while lockout is active.
///
/// Requires the host app to hold the Accessibility entitlement; without it
/// `CGEvent.tapCreate` will succeed at install time but the tap will be
/// disabled by the OS at first event. The getting-started flow walks the
/// user through granting this permission in System Settings.
///
/// This is a best-effort deterrent — a determined user with root access can
/// still bypass via the command line. v0.2's privileged helper will add a
/// second layer at a higher privilege level.
final class LockoutKeyInterceptor {
    /// The live CGEvent tap port, or `nil` when stopped.
    private var eventTap: CFMachPort?

    /// Main run-loop source wrapping `eventTap`, or `nil` when stopped.
    private var source: CFRunLoopSource?

    /// Whether the tap is currently installed on the main run loop.
    var isActive: Bool {
        eventTap != nil
    }

    /// Installs the event tap. Safe to call repeatedly; no-ops when already
    /// running. If the tap fails to create (e.g. accessibility not granted),
    /// this silently returns without setting `eventTap` — callers should
    /// check `isActive` if they need to know whether interception took.
    func start() {
        guard eventTap == nil else {
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
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

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: nil
            )
        else {
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        source = runLoopSource
    }

    /// Removes the event tap from the main run loop. Safe to call when not
    /// started. Idempotent.
    func stop() {
        guard let tap = eventTap, let source else {
            eventTap = nil
            source = nil
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = nil
        self.source = nil
    }
}
