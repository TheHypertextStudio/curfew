/// Pure policy describing whether Curfew's lockout enforcement is fully
/// operational, and — when it isn't — why and how the user can repair it.
///
/// Kept free of any system dependency so it is trivially testable: callers feed
/// in the two facts that gate enforcement (Accessibility trust and the keyboard
/// shield's expected-vs-actual state) and get back a value carrying both the
/// machine-readable state and the user-facing remediation copy.
///
/// Surfaced as a settings/menu banner and a menu-bar badge so a silently
/// degraded shield (revoked Accessibility, a downed event tap) cannot masquerade
/// as active enforcement.
enum PrivilegedEnforcementAvailability: Equatable {
    case notRequired
    case ready
    case unavailable
    case unauthorized
    case stale
    case registrationFailed
}

enum EnforcementHealth: Equatable {
    /// Enforcement is fully operational — Accessibility is trusted and the
    /// keyboard shield is running whenever it is expected to be.
    case active

    /// Accessibility trust is missing, so the keyboard shield cannot run at all.
    case degradedNoAccessibility

    /// Accessibility is trusted and the shield was expected to be running, but
    /// its event tap is down — keystrokes are no longer being intercepted.
    case degradedTapDown

    case degradedHelperUnavailable
    case degradedHelperUnauthorized
    case degradedHelperStale
    case degradedHelperRegistration

    /// Whether enforcement is fully operational. `true` only for ``active``.
    var isFullyActive: Bool {
        self == .active
    }

    /// Resolves the enforcement health from the facts that gate the keyboard
    /// shield.
    ///
    /// - Parameters:
    ///   - isAccessibilityTrusted: Whether the app currently holds Accessibility
    ///     trust (`AXIsProcessTrusted`). Without it the shield cannot run.
    ///   - tapExpectedActive: Whether the event tap is supposed to be running
    ///     right now (typically `true` only during an active lockout).
    ///   - tapIsActive: Whether the event tap is actually enabled.
    /// - Returns: ``degradedNoAccessibility`` when trust is missing, otherwise
    ///   ``degradedTapDown`` when an expected tap is down, otherwise ``active``.
    ///   An idle tap that is not expected to be running is healthy.
    static func resolve(
        isAccessibilityTrusted: Bool,
        tapExpectedActive: Bool,
        tapIsActive: Bool,
        helperAvailability: PrivilegedEnforcementAvailability = .notRequired
    ) -> EnforcementHealth {
        if !isAccessibilityTrusted {
            .degradedNoAccessibility
        } else if tapExpectedActive, !tapIsActive {
            .degradedTapDown
        } else {
            switch helperAvailability {
            case .notRequired, .ready:
                .active
            case .unavailable:
                .degradedHelperUnavailable
            case .unauthorized:
                .degradedHelperUnauthorized
            case .stale:
                .degradedHelperStale
            case .registrationFailed:
                .degradedHelperRegistration
            }
        }
    }

    /// Short banner headline for a degraded state, or `nil` when ``active``.
    /// Both degraded headlines lead with the fact that enforcement is not active.
    var bannerTitle: String? {
        switch self {
        case .active:
            nil
        case .degradedNoAccessibility:
            Self.noAccessibilityBannerTitle
        case .degradedTapDown:
            Self.tapDownBannerTitle
        case .degradedHelperUnavailable, .degradedHelperUnauthorized,
             .degradedHelperStale, .degradedHelperRegistration:
            Self.helperBannerTitle
        }
    }

    /// Longer banner body explaining how to restore enforcement for a degraded
    /// state, or `nil` when ``active``.
    var bannerDetail: String? {
        switch self {
        case .active:
            nil
        case .degradedNoAccessibility:
            Self.noAccessibilityBannerDetail
        case .degradedTapDown:
            Self.tapDownBannerDetail
        case .degradedHelperUnavailable:
            "The privileged helper is unavailable. Install or approve it in "
                + "Settings → Integrations."
        case .degradedHelperUnauthorized:
            "The privileged helper rejected Curfew's signature. Reinstall a "
                + "signed release build."
        case .degradedHelperStale:
            "The privileged helper heartbeat is stale. Relaunch Curfew before "
                + "relying on enforcement."
        case .degradedHelperRegistration:
            "The privileged helper could not register. Review Settings → "
                + "Integrations and try again."
        }
    }

    /// SF Symbol name for the menu-bar warning badge in a degraded state, or
    /// `nil` when ``active`` (no badge).
    var menuBarBadgeSymbol: String? {
        switch self {
        case .active:
            nil
        case .degradedNoAccessibility, .degradedTapDown,
             .degradedHelperUnavailable, .degradedHelperUnauthorized,
             .degradedHelperStale, .degradedHelperRegistration:
            Self.degradedBadgeSymbol
        }
    }

    /// Single-line message for the tight menu-bar popover, or `nil` when
    /// ``active`` (the popover shows no warning row). Deliberately terser than
    /// ``bannerDetail`` because the popover is fixed-width with little vertical
    /// room; the full remediation steps live in the main window and Settings.
    var compactPopoverMessage: String? {
        switch self {
        case .active:
            nil
        case .degradedNoAccessibility:
            "Enforcement is not active — Curfew can't block your keyboard "
                + "without Accessibility access."
        case .degradedTapDown:
            "Enforcement is not active — the keyboard shield was interrupted."
        case .degradedHelperUnavailable:
            "Enforcement is not active — the privileged helper is unavailable."
        case .degradedHelperUnauthorized:
            "Enforcement is not active — the privileged helper rejected this build."
        case .degradedHelperStale:
            "Enforcement is not active — the privileged helper heartbeat is stale."
        case .degradedHelperRegistration:
            "Enforcement is not active — the privileged helper could not register."
        }
    }

    /// Short status headline for the Settings enforcement panel. Unlike
    /// ``bannerTitle`` this is defined for ``active`` too, so the panel can
    /// state the healthy case plainly rather than vanishing.
    var settingsStatusTitle: String {
        switch self {
        case .active:
            "Enforcement is active"
        case .degradedNoAccessibility:
            Self.noAccessibilityBannerTitle
        case .degradedTapDown:
            Self.tapDownBannerTitle
        case .degradedHelperUnavailable, .degradedHelperUnauthorized,
             .degradedHelperStale, .degradedHelperRegistration:
            Self.helperBannerTitle
        }
    }

    /// Reassurance body shown in the Settings panel when enforcement is
    /// ``active``; the degraded cases use ``bannerDetail`` instead.
    static let activeSettingsDetail =
        "Accessibility is trusted and the keyboard shield runs whenever a "
            + "lockout is active. Nothing to do here."

    /// Whether this state should offer the "open Accessibility settings"
    /// fix-it affordance. `true` for every degraded case — re-granting
    /// Accessibility (or relaunching) is the remediation for both — and
    /// `false` when ``active``.
    var offersAccessibilityRemediation: Bool {
        self == .degradedNoAccessibility || self == .degradedTapDown
    }

    /// Headline shown when Accessibility trust is missing.
    static let noAccessibilityBannerTitle =
        "Enforcement is not active"

    /// Remediation body shown when Accessibility trust is missing.
    static let noAccessibilityBannerDetail =
        "Curfew can't block your keyboard without Accessibility access. "
            + "Grant Accessibility to Curfew in System Settings → Privacy & "
            + "Security → Accessibility, then relaunch."

    /// Headline shown when the expected keyboard shield tap is down.
    static let tapDownBannerTitle =
        "Enforcement is not active"

    /// Remediation body shown when the expected keyboard shield tap is down.
    static let tapDownBannerDetail =
        "The keyboard shield was interrupted, so shortcuts are no longer "
            + "blocked. Re-grant Accessibility to Curfew or relaunch the app to "
            + "restore enforcement."

    static let helperBannerTitle = "Enforcement is not active"

    /// SF Symbol used for every degraded menu-bar badge.
    static let degradedBadgeSymbol = "exclamationmark.triangle.fill"
}

import CurfewKit
