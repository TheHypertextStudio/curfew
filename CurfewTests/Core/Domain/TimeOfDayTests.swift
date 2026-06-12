@testable import Curfew
import Foundation
import Testing

/// Tests for the ``TimeOfDay`` hour → phase mapping that drives the runtime
/// Dock icon.
struct TimeOfDayTests {
    @Test("Each hour maps to the expected phase")
    func hourBoundaries() {
        // Night runs 21:00–04:59.
        #expect(TimeOfDay.at(hour: 0) == .night)
        #expect(TimeOfDay.at(hour: 4) == .night)
        // Dawn 05:00–08:59.
        #expect(TimeOfDay.at(hour: 5) == .dawn)
        #expect(TimeOfDay.at(hour: 8) == .dawn)
        // Day 09:00–16:59.
        #expect(TimeOfDay.at(hour: 9) == .day)
        #expect(TimeOfDay.at(hour: 16) == .day)
        // Dusk 17:00–20:59.
        #expect(TimeOfDay.at(hour: 17) == .dusk)
        #expect(TimeOfDay.at(hour: 20) == .dusk)
        // Back to night.
        #expect(TimeOfDay.at(hour: 21) == .night)
        #expect(TimeOfDay.at(hour: 23) == .night)
    }

    @Test("Every phase resolves a distinct Dock icon asset name")
    func assetNames() {
        let names = Set(TimeOfDay.allCases.map(\.dockIconAssetName))
        #expect(names.count == TimeOfDay.allCases.count)
        #expect(TimeOfDay.dusk.dockIconAssetName == "DockIconDusk")
    }
}
