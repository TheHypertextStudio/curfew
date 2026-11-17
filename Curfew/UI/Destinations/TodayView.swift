import AppKit
import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// "Today" workspace destination. A thin adapter: reads the model's resolved
/// ``TodayPresentation`` and the one thing, and forwards actions.
struct TodayView: View {
    @Environment(CurfewAppModel.self) private var model

    var body: some View {
        TodaySundownView(
            horizon: model.horizonFrame,
            isDayRunning: model.isHorizonDayRunning,
            presentation: model.todayPresentation,
            oneThing: model.todaysOneThing,
            voice: model.voice,
            showAccessibilityWarning: model.showsHealthWarnings && !model.isAccessibilityTrusted,
            showAccessibilityGranted: model.accessibilityJustGranted,
            onTurnOn: {
                if model.settings.hasCompletedInitialSetup {
                    model.start()
                } else {
                    model.showGettingStarted()
                }
            },
            onMoreTime: { model.confirmExtensionRequest() },
            onCallItADay: { model.callItADay() },
            onOneThingDone: { model.setOneThingDone($0) },
            onSaveOneThing: { model.saveTodaysOneThing($0) },
            onResolveAccessibility: { model.requestAccessibilityAccess() }
        )
    }
}
