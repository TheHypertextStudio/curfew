import SwiftUI
import CurfewKit
import WidgetKit

/// WidgetKit bundle entry point. The target also compiles Curfew's shared
/// domain/settings/storage sources plus `WidgetSharedStateStore` so the
/// extension stays in sync with the host app's scheduling model.
@main
struct CurfewWidgetBundle: WidgetBundle {
    /// Bundle body: the timeline widget plus, on macOS 15+, the Control
    /// Center control. The control is gated behind `@available` because
    /// `ControlWidget` is unavailable on earlier systems; the bundle still
    /// ships the timeline widget there.
    var body: some Widget {
        CurfewWidget()
        if #available(macOS 15.0, *) {
            CurfewControlWidget()
        }
    }
}

/// The lone Curfew widget. Static configuration (no user-tunable
/// intent parameters yet); provider feeds `CurfewWidgetView` snapshots
/// pulled from the shared App Group container.
struct CurfewWidget: Widget {
    /// Stable widget identifier. Used by `WidgetCenter` to reload
    /// timelines from the host app.
    let kind = CurfewWidgetIdentity.kind

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
