import SwiftUI
import WidgetKit

// MARK: - Widget definition

/// WidgetKit bundle entry point. One widget today; bundle exists so
/// future Curfew widgets (weekly summary, multi-device dashboard) can
/// be added without restructuring the target.
@main
struct CurfewWidgetBundle: WidgetBundle {
    /// Single-widget bundle body.
    var body: some Widget {
        CurfewWidget()
    }
}

/// The lone Curfew widget. Static configuration (no user-tunable
/// intent parameters yet); provider feeds `CurfewWidgetView` snapshots
/// pulled from the shared App Group container.
struct CurfewWidget: Widget {
    /// Stable widget identifier. Used by `WidgetCenter` to reload
    /// timelines from the host app.
    let kind = "studio.hypertext.curfew.widget"

    /// `StaticConfiguration` paired with the provider and view.
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CurfewWidgetProvider()) { entry in
            CurfewWidgetView(entry: entry)
        }
        .configurationDisplayName("Curfew")
        .description("See your current enforcement phase and time remaining.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    CurfewWidget()
} timeline: {
    CurfewWidgetEntry.placeholder
}
