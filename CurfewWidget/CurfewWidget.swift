import CurfewKit
import SwiftUI
import WidgetKit

/// WidgetKit bundle entry point: the timeline widget and the Control Center
/// control.
@main
struct CurfewWidgetBundle: WidgetBundle {
    var body: some Widget {
        CurfewWidget()
        CurfewControlWidget()
    }
}

/// The time left until curfew, and the curfew time.
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
        .description("Time left until curfew.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    CurfewWidget()
} timeline: {
    CurfewWidgetEntry.placeholder
}
