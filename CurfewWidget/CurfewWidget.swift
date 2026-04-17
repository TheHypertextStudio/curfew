import SwiftUI
import WidgetKit

// MARK: - Widget definition

@main
struct CurfewWidgetBundle: WidgetBundle {
    var body: some Widget {
        CurfewWidget()
    }
}

struct CurfewWidget: Widget {
    let kind = "studio.hypertext.curfew.widget"

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
