import CoreGraphics
import CurfewKit
import Foundation

/// The time card's grid, in the units of a 320 by 440 card. Every view and
/// the exported image scale these by the card's width, so the card on screen
/// and the shared image are one picture at two sizes. One margin all round
/// and fixed vertical steps: nothing on the card is placed by eye.
enum JournalTimeCardLayout {
    static let size = CGSize(width: 320, height: 440)
    /// Width over height: 8:11.
    static let aspectRatio = 8.0 / 11.0
    static let margin = 24.0
    static let contentWidth = 272.0
    /// The rounded corners' radius.
    static let cornerRadius = 14.0
    /// How far the clipped top-right corner cuts along each edge.
    static let clippedCorner = 28.0

    // MARK: Vertical steps

    /// The dusk sky band at the top, its bottom edge the horizon.
    static let skyHeight = 168.0
    /// The mark, wordmark and year sit on this line, centred.
    static let headerCenterY = 38.0
    /// The headline value's baseline, on the sky.
    static let heroBaseline = 144.0
    /// The line of words under the sky.
    static let lineBaseline = 198.0
    /// Where the punches go: the full content width, between the words and
    /// the footer.
    static let punchArea = CGRect(x: 24, y: 216, width: 272, height: 168)
    /// The footer's baseline, one margin above the bottom edge.
    static let footerBaseline = 416.0

    // MARK: Type sizes

    static let heroSize = 84.0
    static let heroUnitSize = 30.0
    static let lineSize = 17.0
    static let markSize = 13.0
    static let footerSize = 10.5
    static let axisSize = 9.5

    // MARK: Holes

    /// A hole's diameter as a share of its grid pitch.
    static let holeShare = 0.64
    /// The smallest hole worth punching, as a diameter.
    static let minimumHoleDiameter = 5.0
    /// Skyline pitches: never below the minimum, aiming for comfortable,
    /// and capped so a quiet year does not punch coins.
    static let minimumPitch = 8.0
    static let comfortablePitch = 10.5
    static let maximumPitch = 12.0
    /// The skyline's holes stand on this line; the axis runs just under it.
    static let skylineHoleBottom = 364.0
    static let skylineHoleHeight = skylineHoleBottom - punchArea.minY
    static let skylineAxisY = 369.0
    static let skylineLabelBaseline = punchArea.maxY

    // MARK: Calendar grid

    /// Height of a band's month labels, above its first row.
    static let monthLabelHeight = 12.0
    /// Space between the two half-year bands.
    static let bandGap = 16.0

    struct CalendarGrid: Equatable {
        let columnPitch: Double
        let rowPitch: Double
        let holeRadius: Double
        let bandHeight: Double
        /// Both bands and the gap between them.
        var height: Double {
            bandHeight * 2 + bandGap
        }

        /// Top of `band`, centring both bands in the punch area.
        func bandTop(_ band: Int) -> Double {
            punchArea.minY + (punchArea.height - height) / 2
                + Double(band) * (bandHeight + bandGap)
        }
    }

    /// Square cells across the full content width, squeezed vertically only
    /// when seven rows a week would not fit.
    static func calendarGrid(rows: Int, columns: Int) -> CalendarGrid {
        let columnPitch = contentWidth / Double(max(columns, 1))
        let fit = (punchArea.height - bandGap - monthLabelHeight * 2) / Double(max(rows, 1) * 2)
        let rowPitch = min(columnPitch, fit)
        return CalendarGrid(
            columnPitch: columnPitch,
            rowPitch: rowPitch,
            holeRadius: min(columnPitch, rowPitch) * holeShare / 2,
            bandHeight: monthLabelHeight + rowPitch * Double(rows)
        )
    }
}

/// One round cut-out, in card units.
struct JournalTimeCardHole: Equatable, Sendable {
    let centerX: Double
    let centerY: Double
    let radius: Double
}

extension JournalTimeCardHole {
    var rect: CGRect {
        CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)
    }
}
