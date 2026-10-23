import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// App-owned timeline adapter for the shared, stateless atmosphere renderer.
struct SundownSky: View {
    var moment: SkyMoment
    var isVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 24.0,
            paused: reduceMotion || !isVisible
        )) { timeline in
            AtmosphereSky(
                moment: moment,
                date: timeline.date,
                reduceMotion: reduceMotion
            )
        }
    }
}
