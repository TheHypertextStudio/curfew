import AppIntents
import CurfewKit
import SwiftUI
import WidgetKit

/// Control Center widget (macOS 15+) that surfaces Curfew's current phase and
/// minutes-until-curfew, and opens the app when tapped.
///
/// It reads the same shared snapshot the timeline widget reads
/// (`WidgetSharedStateStore` → settings → `CurfewEnforcementEngine`), so the
/// control, the timeline widget, and the app never disagree about state.
@available(macOS 15.0, *)
struct CurfewControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: CurfewControlIdentity.kind,
            provider: CurfewControlValueProvider()
        ) { value in
            ControlWidgetButton(action: OpenCurfewControlIntent()) {
                Label(value.label, systemImage: value.symbolName)
            }
        }
        .displayName("Curfew Status")
        .description("See time until curfew and open Curfew.")
    }
}

/// Stable Control Center widget `kind`. Flavor-suffixed so a development build
/// stays distinct from production, mirroring ``CurfewWidgetIdentity``.
enum CurfewControlIdentity {
    static let kind =
        "studio.hypertext.curfew\(CurfewFlavor.current.identifierSuffix).control"
}

/// Supplies the control's display value, recomputed each time Control Center
/// refreshes. Reuses the timeline provider's read path so the control matches
/// the rest of the surface.
@available(macOS 15.0, *)
struct CurfewControlValueProvider: ControlValueProvider {
    /// What the control renders: a short label and an SF Symbol keyed to phase.
    struct Value {
        var label: String
        var symbolName: String
    }

    /// Gallery preview value (no live read).
    var previewValue: Value {
        Value(label: "Curfew", symbolName: "moon.stars")
    }

    /// Live value pulled from the shared snapshot at refresh time.
    ///
    /// Prefers the live ``WidgetEnforcementSnapshot`` the app writes on every
    /// phase/warning-stage transition — it reflects active extensions and
    /// overrides, which the settings-only estimate below cannot. Without
    /// this, the doc comment's promise that "the control, the timeline
    /// widget, and the app never disagree" didn't hold: this control
    /// recomputed independently with `extensionMinutesGrantedToday: 0,
    /// overrideUntil: nil`, so it could show "Locked" while an active
    /// extension had the rest of the app at "Working".
    func currentValue() async throws -> Value {
        let now = Date()
        if let live = WidgetSharedStateStore().loadEnforcement(),
           now.timeIntervalSince(live.updatedAt) < 90 * 60,
           let phase = EnforcementPhase(widgetToken: live.phase) {
            return value(for: phase, minutesRemaining: live.minutesRemaining)
        }

        let settings = WidgetSharedStateStore().loadSettings()
        let eval = CurfewEnforcementEngine().evaluate(
            at: now,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: settings.warningIntervals
        )
        return value(for: eval.phase, minutesRemaining: eval.minutesRemaining)
    }

    private func value(for phase: EnforcementPhase, minutesRemaining: Int) -> Value {
        switch phase {
        case .locked:
            Value(label: "Locked", symbolName: "lock.fill")
        case .dayOff:
            Value(label: "Day off", symbolName: "sun.max")
        case .working:
            Value(label: "\(minutesRemaining) min", symbolName: "moon.stars")
        case .warning:
            Value(label: "\(minutesRemaining) min", symbolName: "exclamationmark.triangle")
        }
    }
}

private extension EnforcementPhase {
    /// Maps the lowercase string token `WidgetEnforcementSnapshot`/
    /// `CurfewWidgetEntry` carry back to the real enum, mirroring
    /// `CurfewWidgetProvider.phaseToken(_:)` in reverse.
    init?(widgetToken: String) {
        switch widgetToken {
        case "working": self = .working
        case "warning": self = .warning
        case "locked": self = .locked
        case "day_off": self = .dayOff
        default: return nil
        }
    }
}

/// Opens Curfew when the control is tapped. Lives in the widget extension so
/// the control can reference it; `openAppWhenRun` brings the host app forward.
@available(macOS 15.0, *)
struct OpenCurfewControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Curfew"

    /// Tapping the control should foreground the app.
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
