import SwiftUI

/// Shared degraded-enforcement banner driven by ``EnforcementHealth``.
///
/// Surfaces the same honest "enforcement is not active" signal in every place
/// it matters — the main-window overview, the Settings enforcement panel, and
/// (in a compact variant) the menu-bar popover — so a silently broken lockout
/// (revoked Accessibility, a downed keyboard-shield tap) cannot masquerade as
/// active enforcement on any one surface while looking fine on another.
///
/// Renders nothing when ``EnforcementHealth/active``; the title/detail copy and
/// the warning glyph come straight from the pure ``EnforcementHealth`` policy so
/// the wording stays consistent everywhere and is unit-tested once.
struct EnforcementHealthBanner: View {
    /// The current verdict. The banner is empty unless this is degraded.
    let health: EnforcementHealth
    /// Invoked when the user taps the fix-it button. Callers wire this to
    /// `model.requestAccessibilityAccess()`, which prompts for trust and opens
    /// System Settings — both guarded against the unit-test host inside the
    /// model, so this component never triggers a TCC prompt itself.
    let onFix: () -> Void

    /// Degraded banner, or an empty view when enforcement is active.
    var body: some View {
        if let title = health.bannerTitle, let detail = health.bannerDetail {
            CurfewPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: EnforcementHealth.degradedBadgeSymbol)
                        .font(CurfewTypography.bodyEmphasis(14))
                        .foregroundStyle(CurfewTheme.warning)

                    Text(detail)
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if health.offersAccessibilityRemediation {
                        Button("Open Accessibility Settings", action: onFix)
                            .buttonStyle(CurfewSecondaryButtonStyle())
                    }
                }
            }
        }
    }
}

/// Compact degraded-enforcement warning for the fixed-width menu-bar popover.
///
/// The full-height ``EnforcementHealthBanner`` is too tall for the popover, so
/// this variant shows a single warning line plus a tight fix-it button. Both
/// fall back to silence when enforcement is ``EnforcementHealth/active``.
struct CompactEnforcementHealthWarning: View {
    /// The current verdict. The warning is empty unless this is degraded.
    let health: EnforcementHealth
    /// Fix-it action — see ``EnforcementHealthBanner/onFix``.
    let onFix: () -> Void

    /// Compact warning row, or an empty view when enforcement is active.
    var body: some View {
        if let message = health.compactPopoverMessage {
            CurfewPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: EnforcementHealth.degradedBadgeSymbol)
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)

                    if health.offersAccessibilityRemediation {
                        Button("Fix Accessibility", action: onFix)
                            .buttonStyle(CurfewSecondaryButtonStyle())
                    }
                }
            }
        }
    }
}
