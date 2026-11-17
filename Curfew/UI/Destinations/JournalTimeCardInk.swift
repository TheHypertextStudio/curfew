import CurfewAtmosphere
import SwiftUI

/// The time card's colours for one style. The card always draws in its own
/// colours, whatever the appearance, and always sits on a stage that
/// contrasts with its stock so the holes read as holes.
struct JournalTimeCardInk {
    let stock: Color
    /// The hairline around the card's edge.
    let edge: Color
    let print: Color
    let softPrint: Color
    /// Words on the sky, in either stock.
    let onSky: Color
    /// The surface the card sits on, seen through the holes.
    let stage: Color
    /// Whether the stage is dark, so controls on it can follow.
    let stageIsDark: Bool
    /// The card's thickness shadowing the top edge of each hole.
    let holeShadow: Color
    let shadow: Color

    init(_ style: JournalTimeCardStyle) {
        typealias Fixed = SundownPalette.TimeCard
        let night = style.sky.palette.night
        self.onSky = Fixed.onSky
        switch style.stock {
        case .night:
            // The stock takes the sky's own night, so the card is one object.
            let tone = night[1].mixed(night[2], 0.55)
            self.stock = tone.color
            self.edge = tone.mixed(HorizonRGB(1, 1, 1), 0.12).color
            self.print = Fixed.nightPrint
            self.softPrint = print.opacity(0.66)
            self.stage = Fixed.table
            self.stageIsDark = false
            self.holeShadow = Fixed.nightHoleShadow
            self.shadow = Fixed.nightShadow
        case .paper:
            let ink = night[1].mixed(Fixed.paperInk, 0.7)
            self.stock = Fixed.color(Fixed.paper)
            self.edge = Fixed.paperEdge
            self.print = ink.color
            self.softPrint = ink.mixed(Fixed.paper, 0.42).color
            self.stage = night[1].mixed(night[2], 0.35).color
            self.stageIsDark = true
            self.holeShadow = Color.black.opacity(0.45)
            self.shadow = Color.black.opacity(0.5)
        }
    }
}

private extension HorizonRGB {
    func mixed(_ other: HorizonRGB, _ amount: Double) -> HorizonRGB {
        HorizonRGB(
            red + (other.red - red) * amount,
            green + (other.green - green) * amount,
            blue + (other.blue - blue) * amount
        )
    }

    var color: Color {
        SundownPalette.TimeCard.color(self)
    }
}
