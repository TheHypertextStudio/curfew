import AppKit
import ApplicationServices

/// Injectable seam over the macOS Accessibility-trust check.
///
/// Curfew's keyboard lockout is implemented with a `CGEvent` tap, which macOS
/// only delivers events to when the app holds Accessibility trust
/// (`AXIsProcessTrusted`). Without it the tap is installed but never fires, so
/// the lockout silently does nothing. Routing that check through a protocol lets
/// model logic gate on trust (and decide when to prompt) while staying unit
/// testable: the real `AX*` C symbols cannot be exercised headlessly, so tests
/// substitute a fake instead of triggering a real system prompt.
protocol AccessibilityAuthorizing {
    /// Whether the app currently holds Accessibility trust. Mirrors
    /// `AXIsProcessTrusted()`.
    func isTrusted() -> Bool

    /// Asks macOS to surface the Accessibility-trust prompt if trust is not
    /// already granted, returning the current trust state.
    ///
    /// - Returns: `true` if the app is already trusted; otherwise `false` while
    ///   the system prompt is shown. The user must still grant access in System
    ///   Settings and relaunch, so a `false` here is expected on first run.
    @discardableResult
    func promptForTrust() -> Bool
}

/// Production `AccessibilityAuthorizing` backed by the live `AX*` C APIs.
struct SystemAccessibilityAuthorization: AccessibilityAuthorizing {
    /// Reports the live Accessibility-trust state via `AXIsProcessTrusted()`.
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the macOS Accessibility-trust prompt via
    /// `AXIsProcessTrustedWithOptions` with the prompt option enabled.
    @discardableResult
    func promptForTrust() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    /// Opens the Accessibility pane of System Settings → Privacy & Security so
    /// the user can grant Curfew the access its keyboard lockout requires.
    static func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }
}
