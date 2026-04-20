import Foundation
import OSLog

private let widgetMirrorLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "widget-mirror"
)

@MainActor
extension CurfewAppModel {
    func syncWidgetSharedState(_ settings: CurfewSettings? = nil) {
        do {
            try WidgetSharedStateStore().sync(settings: settings ?? self.settings)
        } catch {
            widgetMirrorLogger.error(
                "failed to sync widget shared state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
