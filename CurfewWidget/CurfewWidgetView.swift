import SwiftUI
import WidgetKit

/// WidgetKit wrapper around ``CurfewWidgetFace``: picks the size and gives
/// the face its container background.
struct CurfewWidgetView: View {
    let entry: CurfewWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        CurfewWidgetFace(
            presentation: CurfewWidgetPresentation(
                phase: entry.phase,
                minutesRemaining: entry.minutesRemaining,
                lockDate: entry.lockDate,
                unlockDate: entry.unlockDate
            ),
            size: family == .systemSmall ? .small : .medium
        )
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
