import SwiftUI

/// The SF Symbol for each concept in the icon list. Symbols lead every control
/// and status line at the text's weight. `HorizonSymbolTests` checks that each
/// name exists, so a wrong name fails a test instead of drawing nothing.
enum HorizonSymbol: String, CaseIterable, Sendable {
    case curfew
    case sunrise
    case locked
    case override
    case moreTime
    case oneThing
    case oneThingDone
    case lastNight
    case today
    case schedule
    case journal

    var systemName: String {
        switch self {
        case .curfew: "sunset"
        case .sunrise: "sunrise"
        case .locked: "lock"
        case .override: "lock.open"
        // SF Symbols has no clock with a plus; this is the closest "more time".
        case .moreTime: "goforward.plus"
        case .oneThing: "circle"
        case .oneThingDone: "checkmark.circle"
        case .lastNight: "moon"
        case .today: "sun.max"
        case .schedule: "calendar"
        case .journal: "book"
        }
    }

    var image: Image {
        Image(systemName: systemName)
    }
}

extension Label where Title == Text, Icon == Image {
    /// A label led by a Horizon symbol.
    init(_ title: some StringProtocol, horizonSymbol symbol: HorizonSymbol) {
        self.init(title, systemImage: symbol.systemName)
    }
}
