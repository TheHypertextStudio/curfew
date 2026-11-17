import AppKit
import CurfewAtmosphere
import SwiftUI

/// The time card's picture: the sky band with the mark, year and headline,
/// the line of words, the punches cut clean through the stock, and the
/// footer. Every size is a share of the width, so the card on screen and the
/// exported image are one picture at two sizes. The holes show whatever is
/// behind the card, so it must sit on its ``JournalTimeCardInk/stage``.
struct JournalTimeCardArt<Sky: View>: View {
    let card: JournalYearReview.Card
    let style: JournalTimeCardStyle
    /// How far the card has lifted off its stage, 0 to 1.
    var lift: Double = 0
    /// The Horizon scene for the style's sky. The art sizes it so its
    /// horizon is the sky band's bottom edge.
    @ViewBuilder var sky: Sky

    typealias Layout = JournalTimeCardLayout

    /// The sky behind the card: dusk, the sun sitting on the horizon near the
    /// right margin. Fixed, so the card looks the same whenever it is opened.
    static var skyFrame: HorizonFrame {
        HorizonFrame(
            sun: HorizonPoint(
                x: 0.835,
                y: HorizonGeometry.horizon + HorizonGeometry.sunRadius * 0.35
            ),
            sunWeight: 1,
            moon: HorizonPoint(x: 0.5, y: -1),
            moonWeight: 0,
            elevation: JournalTimeCardSky.swatchElevation,
            moonPhase: 0
        )
    }

    /// The scene's height in card units: tall enough that the scene's
    /// horizon falls on the sky band's bottom edge.
    static var skySceneHeight: Double {
        Layout.skyHeight / (1 - HorizonGeometry.horizon)
    }

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / Layout.size.width
            let ink = JournalTimeCardInk(style)
            let holes = holes
            ZStack(alignment: .topLeading) {
                shadow(unit: unit, ink: ink, holes: holes)
                ZStack(alignment: .topLeading) {
                    ink.stock
                    sky
                        .frame(width: proxy.size.width, height: Self.skySceneHeight * unit)
                        .frame(
                            width: proxy.size.width, height: Layout.skyHeight * unit,
                            alignment: .top
                        )
                        .clipped()
                    Canvas { context, _ in
                        context.scaleBy(x: unit, y: unit)
                        JournalTimeCardPrint(card: card, style: style, ink: ink).draw(in: &context)
                    }
                }
                .mask {
                    Canvas { context, _ in
                        context.scaleBy(x: unit, y: unit)
                        var path = Layout.outline
                        for hole in holes {
                            path.addEllipse(in: hole.rect)
                        }
                        context.fill(path, with: .color(.black), style: FillStyle(eoFill: true))
                    }
                }
                Canvas { context, _ in
                    context.scaleBy(x: unit, y: unit)
                    drawHoleShadows(in: &context, ink: ink, holes: holes)
                }
            }
        }
        .aspectRatio(Layout.aspectRatio, contentMode: .fit)
    }

    private var holes: [JournalTimeCardHole] {
        switch style.punches {
        case .calendar: JournalTimeCardPrint.calendarHoles(card.calendar)
        case .skyline: card.skyline.holes
        }
    }

    // MARK: - Shape

    /// The drop shadow, drawn on the stage around the card and cleared again
    /// at every hole so the holes never fill with it.
    private func shadow(unit: Double, ink: JournalTimeCardInk, holes: [JournalTimeCardHole])
        -> some View {
        let pad = 60.0
        return Canvas { context, _ in
            context.scaleBy(x: unit, y: unit)
            context.translateBy(x: pad, y: pad)
            var contact = context
            contact.addFilter(.blur(radius: (1.2 + lift * 1.2) * unit))
            contact.fill(
                Layout.outline.offsetBy(dx: 0, dy: 1.2 + lift * 1.6),
                with: .color(ink.shadow.opacity(0.9))
            )
            var ambient = context
            ambient.addFilter(.blur(radius: (12 + lift * 8) * unit))
            ambient.fill(
                Layout.outline.offsetBy(dx: 0, dy: 10 + lift * 8),
                with: .color(ink.shadow.opacity(0.75 + lift * 0.15))
            )
            context.blendMode = .clear
            var cut = Path()
            for hole in holes {
                cut.addEllipse(in: hole.rect)
            }
            context.fill(cut, with: .color(.black))
        }
        .padding(-pad * unit)
        .allowsHitTesting(false)
    }

    /// A thin crescent inside the top edge of each hole: the stock's own
    /// thickness shading the stage below. Nothing else touches a hole.
    private func drawHoleShadows(
        in context: inout GraphicsContext, ink: JournalTimeCardInk, holes: [JournalTimeCardHole]
    ) {
        guard let radius = holes.first?.radius else { return }
        let drop = max(0.55, radius * 0.22)
        var crescents = Path()
        for hole in holes {
            var crescent = Path(ellipseIn: hole.rect)
            crescent = crescent.subtracting(Path(ellipseIn: hole.rect.offsetBy(dx: 0, dy: drop)))
            crescents.addPath(crescent)
        }
        context.fill(crescents, with: .color(ink.holeShadow))
    }
}

extension JournalTimeCardArt where Sky == AnyView {
    /// The card with its live Horizon sky in the style's palette.
    init(card: JournalYearReview.Card, style: JournalTimeCardStyle, lift: Double = 0) {
        self.init(card: card, style: style, lift: lift) {
            AnyView(
                HorizonSkyView(frame: Self.skyFrame, isDayRunning: false)
                    .environment(\.horizonPalette, style.sky.palette)
            )
        }
    }
}
