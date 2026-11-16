import AppKit
@testable import Curfew
import Testing

/// Every concept in the icon list maps to an SF Symbol that exists, so a typo
/// fails here instead of drawing nothing.
struct HorizonSymbolTests {
    @Test("Every Horizon symbol exists in SF Symbols", arguments: HorizonSymbol.allCases)
    func symbolExists(symbol: HorizonSymbol) {
        #expect(
            NSImage(systemSymbolName: symbol.systemName, accessibilityDescription: nil) != nil,
            "\(symbol.systemName) is not an SF Symbol"
        )
    }

    @Test("The spec's concepts map to their symbols")
    func mapping() {
        #expect(HorizonSymbol.curfew.systemName == "sunset")
        #expect(HorizonSymbol.sunrise.systemName == "sunrise")
        #expect(HorizonSymbol.locked.systemName == "lock")
        #expect(HorizonSymbol.override.systemName == "lock.open")
        // SF Symbols has no clock with a plus; a clockwise arrow with a plus
        // reads as "more time" at text size.
        #expect(HorizonSymbol.moreTime.systemName == "goforward.plus")
        #expect(HorizonSymbol.oneThing.systemName == "circle")
        #expect(HorizonSymbol.oneThingDone.systemName == "checkmark.circle")
        #expect(HorizonSymbol.lastNight.systemName == "moon")
        #expect(HorizonSymbol.today.systemName == "sun.max")
        #expect(HorizonSymbol.schedule.systemName == "calendar")
        #expect(HorizonSymbol.journal.systemName == "book")
        #expect(HorizonSymbol.allCases.count == 11)
    }
}
