import CurfewKit
import SwiftUI

/// Everything printed on the time card, drawn in card units: the header
/// and headline on the sky, the line of words, the punch pattern's marks and
/// labels, the footer and the edge. The holes themselves are cut by
/// ``JournalTimeCardArt``.
struct JournalTimeCardPrint {
    let card: JournalYearReview.Card
    let style: JournalTimeCardStyle
    let ink: JournalTimeCardInk

    typealias Layout = JournalTimeCardLayout

    func draw(in context: inout GraphicsContext) {
        drawHeader(in: &context)
        drawHeadline(in: &context)
        switch style.punches {
        case .calendar: drawCalendar(in: &context)
        case .skyline: drawSkyline(in: &context)
        }
        let footer = Font.system(size: Layout.footerSize, weight: .semibold, design: .monospaced)
        draw(
            Text(card.workingDaysLabel).font(footer).foregroundStyle(ink.softPrint),
            baseline: Layout.footerBaseline, x: Layout.margin, in: &context
        )
        draw(
            Text(card.lockLabel).font(footer).foregroundStyle(ink.softPrint),
            baseline: Layout.footerBaseline, x: Layout.size.width - Layout.margin,
            alignment: .trailing, in: &context
        )
        context.stroke(Layout.outline, with: .color(ink.edge), lineWidth: 1)
    }

    private func drawHeader(in context: inout GraphicsContext) {
        let center = Layout.headerCenterY
        // The mark: the sun resting on its line, 20 units wide.
        var mark = Path()
        let left = Layout.margin
        mark.addArc(
            center: CGPoint(x: left + 10, y: center + 0.9), radius: 6,
            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
        )
        mark.closeSubpath()
        mark.addRoundedRect(
            in: CGRect(x: left, y: center + 2.4, width: 20, height: 1.9),
            cornerSize: CGSize(width: 0.95, height: 0.95)
        )
        context.fill(mark, with: .color(ink.onSky))
        let type = Font.system(size: Layout.markSize, weight: .bold, design: .rounded)
        let word = context.resolve(Text("Curfew").font(type).foregroundStyle(ink.onSky))
        let size = word.measure(in: CGSize(width: 200, height: 40))
        // Centre the wordmark's box on the header line.
        let baseline = center - size.height / 2 + word.firstBaseline(in: size)
        draw(word, baseline: baseline, x: left + 26, in: &context)
        let year = context.resolve(
            Text(card.yearLabel)
                .font(.system(size: Layout.markSize, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.onSky.opacity(0.9))
        )
        draw(
            year,
            baseline: baseline,
            x: Layout.size.width - Layout.margin,
            alignment: .trailing,
            in: &context
        )
    }

    private func drawHeadline(in context: inout GraphicsContext) {
        let headline = card.headline(style.headline)
        func hero(_ scale: Double)
            -> (GraphicsContext.ResolvedText, GraphicsContext.ResolvedText?) {
            let value = context.resolve(
                Text(headline.value)
                    .font(.system(size: Layout.heroSize * scale, weight: .bold, design: .rounded))
                    .tracking(-0.03 * Layout.heroSize * scale)
                    .foregroundStyle(ink.onSky)
            )
            let unit = headline.unit.map { words in
                context.resolve(
                    Text(words)
                        .font(.system(
                            size: Layout.heroUnitSize * scale,
                            weight: .bold,
                            design: .rounded
                        ))
                        .foregroundStyle(ink.onSky)
                )
            }
            return (value, unit)
        }
        // The value stays clear of the sun near the right margin; a long
        // clock time steps down until it fits.
        let room = Layout.contentWidth - 46
        let unitGap = 6.0
        var scale = 1.0
        var (value, unit) = hero(scale)
        while scale > 0.55 {
            let width = value.measure(in: Self.unbounded).width
                + (unit.map { $0.measure(in: Self.unbounded).width + unitGap * scale } ?? 0)
            if width <= room {
                break
            }
            scale -= 0.05
            (value, unit) = hero(scale)
        }
        // Rounded figures carry a little side bearing; pull them onto the margin.
        let left = Layout.margin - 3 * scale
        let valueWidth = draw(value, baseline: Layout.heroBaseline, x: left, in: &context)
        if let unit {
            draw(
                unit,
                baseline: Layout.heroBaseline,
                x: left + valueWidth + unitGap * scale,
                in: &context
            )
        }

        drawLine(headline.line, in: &context)
    }

    /// The line of words under the sky, stepped down only if a long line
    /// would run past the margin.
    private func drawLine(_ words: String, in context: inout GraphicsContext) {
        var lineScale = 1.0
        func line(_ scale: Double) -> GraphicsContext.ResolvedText {
            context.resolve(
                Text(words)
                    .font(.system(
                        size: Layout.lineSize * scale,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(ink.print)
            )
        }
        var resolved = line(lineScale)
        while resolved.measure(in: Self.unbounded).width > Layout.contentWidth, lineScale > 0.7 {
            lineScale -= 0.04
            resolved = line(lineScale)
        }
        draw(resolved, baseline: Layout.lineBaseline, x: Layout.margin, in: &context)
    }

    // MARK: Calendar

    static func calendarHoles(_ calendar: JournalTimeCardCalendar) -> [JournalTimeCardHole] {
        let grid = Layout.calendarGrid(
            rows: calendar.weekdays.count,
            columns: calendar.columnsPerBand
        )
        return calendar.slots.filter(\.isPunched).map { slot in
            let center = calendarCenter(slot, grid: grid)
            return JournalTimeCardHole(
                centerX: center.x,
                centerY: center.y,
                radius: grid.holeRadius
            )
        }
    }

    private static func calendarCenter(
        _ slot: JournalTimeCardCalendar.Slot, grid: Layout.CalendarGrid
    ) -> CGPoint {
        CGPoint(
            x: Layout.margin + (Double(slot.column) + 0.5) * grid.columnPitch,
            y: grid.bandTop(slot.band) + Layout.monthLabelHeight
                + (Double(slot.row) + 0.5) * grid.rowPitch
        )
    }

    private func drawCalendar(in context: inout GraphicsContext) {
        let calendar = card.calendar
        let grid = Layout.calendarGrid(
            rows: calendar.weekdays.count,
            columns: calendar.columnsPerBand
        )
        var pilots = Path()
        let dot = max(0.85, grid.holeRadius * 0.27)
        for slot in calendar.slots where !slot.isPunched {
            let center = Self.calendarCenter(slot, grid: grid)
            pilots.addEllipse(in: CGRect(
                x: center.x - dot,
                y: center.y - dot,
                width: dot * 2,
                height: dot * 2
            ))
        }
        context.fill(pilots, with: .color(ink.print.opacity(0.4)))
        let type = Font.system(size: Layout.axisSize, weight: .semibold)
        for month in calendar.months {
            draw(
                Text(month.name).font(type).foregroundStyle(ink.softPrint),
                baseline: grid.bandTop(month.band) + Layout.monthLabelHeight - 4.5,
                x: Layout.margin + Double(month.column) * grid.columnPitch
                    + grid.columnPitch / 2 - grid.holeRadius,
                in: &context
            )
        }
    }

    // MARK: Skyline

    private func drawSkyline(in context: inout GraphicsContext) {
        let skyline = card.skyline
        var axis = Path()
        axis.move(to: CGPoint(x: Layout.margin, y: Layout.skylineAxisY))
        axis.addLine(to: CGPoint(x: Layout.size.width - Layout.margin, y: Layout.skylineAxisY))
        context.stroke(axis, with: .color(ink.print.opacity(0.28)), lineWidth: 1)
        let top = max(Layout.punchArea.minY - 4, skyline.patternOrigin.y - 8)
        var curfew = Path()
        curfew.move(to: CGPoint(x: skyline.curfewX, y: top))
        curfew.addLine(to: CGPoint(x: skyline.curfewX, y: Layout.skylineAxisY))
        context.stroke(
            curfew, with: .color(ink.print.opacity(0.9)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
        )

        let type = Font.system(size: Layout.axisSize, weight: .semibold)
        let baseline = Layout.skylineLabelBaseline
        let early = context
            .resolve(Text(skyline.earlyLabel).font(type).foregroundStyle(ink.softPrint))
        let late = context
            .resolve(Text(skyline.lateLabel).font(type).foregroundStyle(ink.softPrint))
        let mark = context.resolve(Text("Curfew").font(type).foregroundStyle(ink.print))
        let earlyWidth = early.measure(in: Self.unbounded).width
        let lateWidth = late.measure(in: Self.unbounded).width
        let markWidth = mark.measure(in: Self.unbounded).width
        let gap = 8.0
        let minX = Layout.margin + earlyWidth + gap + markWidth / 2
        let maxX = Layout.size.width - Layout.margin - lateWidth - gap - markWidth / 2
        // The curfew label sits under its line; a side label that would
        // collide with it steps aside.
        let centre = skyline.curfewX
        if centre >= minX {
            draw(early, baseline: baseline, x: Layout.margin, in: &context)
        }
        if centre <= maxX {
            draw(
                late,
                baseline: baseline,
                x: Layout.size.width - Layout.margin,
                alignment: .trailing,
                in: &context
            )
        }
        let clamped = min(
            max(centre, Layout.margin + markWidth / 2),
            Layout.size.width - Layout.margin - markWidth / 2
        )
        draw(mark, baseline: baseline, x: clamped - markWidth / 2, in: &context)
    }

    // MARK: Text on a baseline

    private static var unbounded: CGSize {
        CGSize(width: 2000, height: 400)
    }

    @discardableResult
    private func draw(
        _ text: Text, baseline: Double, x edge: Double, alignment: HorizontalAlignment = .leading,
        in context: inout GraphicsContext
    ) -> Double {
        draw(context.resolve(text), baseline: baseline, x: edge, alignment: alignment, in: &context)
    }

    /// Draws `text` with its first baseline on `baseline`. Returns its width.
    @discardableResult
    private func draw(
        _ text: GraphicsContext.ResolvedText, baseline: Double, x edge: Double,
        alignment: HorizontalAlignment = .leading, in context: inout GraphicsContext
    ) -> Double {
        let size = text.measure(in: Self.unbounded)
        let left = alignment == .trailing ? edge - size.width : edge
        let top = baseline - text.firstBaseline(in: size)
        context.draw(text, in: CGRect(x: left, y: top, width: size.width, height: size.height))
        return size.width
    }
}

extension JournalTimeCardLayout {
    /// The card's outline: rounded corners, the top right clipped.
    static var outline: Path {
        let width = size.width
        let height = size.height
        let radius = cornerRadius
        let cut = clippedCorner
        let soft = 2.5
        var path = Path()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addArc(
            tangent1End: CGPoint(x: width - cut, y: 0),
            tangent2End: CGPoint(x: width, y: cut), radius: soft
        )
        path.addArc(
            tangent1End: CGPoint(x: width, y: cut),
            tangent2End: CGPoint(x: width, y: height), radius: soft
        )
        path.addArc(
            tangent1End: CGPoint(x: width, y: height),
            tangent2End: CGPoint(x: 0, y: height), radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: 0, y: height),
            tangent2End: CGPoint(x: 0, y: 0), radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: 0, y: 0),
            tangent2End: CGPoint(x: width, y: 0), radius: radius
        )
        path.closeSubpath()
        return path
    }
}
