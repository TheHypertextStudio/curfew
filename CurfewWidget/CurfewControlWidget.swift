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
    func currentValue() async throws -> Value {
        let settings = WidgetSharedStateStore().loadSettings()
        let eval = CurfewEnforcementEngine().evaluate(
            at: Date(),
            schedule: settings.schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: settings.warningIntervals
        )

        switch eval.phase {
        case .locked:
            return Value(label: "Locked", symbolName: "lock.fill")
        case .dayOff:
            return Value(label: "Day off", symbolName: "sun.max")
        case .working:
            return Value(label: "\(eval.minutesRemaining) min", symbolName: "moon.stars")
        case .warning:
            return Value(
                label: "\(eval.minutesRemaining) min",
                symbolName: "exclamationmark.triangle"
            )
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
