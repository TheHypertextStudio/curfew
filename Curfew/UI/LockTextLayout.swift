import CoreGraphics
import CurfewAtmosphere

/// Where the lock's words sit: the clock, the headline and the unlock line,
/// in one block that never lies behind the sun or the moon.
///
/// The moon crosses the model's path through the night and the sun meets the
/// horizon, so the block is placed under the arc of that path and above the
/// horizon, clear of either disc anywhere along it, on any display aspect.
/// Where the preferred size cannot clear, the block shrinks until it does.
/// Each line is held to its slot in the block (one line, scaling down), so
/// the frame is exactly what is drawn.
/// The words the block holds.
struct LockTextContent: Equatable {
    var clock: String
    var period: String?
    var headline: String
    var line: String?
}

struct LockTextLayout: Equatable {
    var block: CGRect
    var clockSize: CGFloat
    var headlineSize: CGFloat
    var lineSize: CGFloat
    var clockHeight: CGFloat
    var headlineHeight: CGFloat
    var lineHeight: CGFloat
    var clockGap: CGFloat
    var lineGap: CGFloat

    /// The larger body's disc radius, in units of the scene's height.
    static let discRadius = HorizonGeometry.sunRadius
    /// Air between a disc and the words, in units of the scene's height.
    static let clearance = 0.025

    static func resolve(
        size: CGSize, content: LockTextContent, compact: Bool, span: HorizonSpan = .fullBleed
    ) -> LockTextLayout {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let horizon = height * (1 - HorizonGeometry.horizon)
        // The block's bottom stays clear of a disc sitting on the horizon.
        let floor = horizon - height * (discRadius + clearance)
        let preferredTop = compact ? height * 0.04 : height * 0.2
        var scale = 1.0
        var candidate = metrics(
            width: width,
            height: height,
            content: content,
            compact: compact,
            scale: scale
        )
        while scale >= 0.3 {
            candidate = metrics(
                width: width, height: height, content: content, compact: compact, scale: scale
            )
            let blockHeight = candidate.block.height
            var top = preferredTop
            while top + blockHeight <= floor {
                let frame = CGRect(
                    x: (width - candidate.block.width) / 2, y: top,
                    width: candidate.block.width, height: blockHeight
                )
                if clearsPath(frame, size: CGSize(width: width, height: height), span: span) {
                    candidate.block = frame
                    return candidate
                }
                top += 2
            }
            scale -= 0.05
        }
        candidate.block.origin = CGPoint(
            x: (width - candidate.block.width) / 2, y: max(0, floor - candidate.block.height)
        )
        return candidate
    }

    /// Whether `frame` stays clear of a disc anywhere on the path.
    static func clearsPath(_ frame: CGRect, size: CGSize, span: HorizonSpan) -> Bool {
        let radius = size.height * (discRadius + clearance)
        var progress = 0.0
        while progress <= 1 {
            let point = span.point(at: progress)
            let center = CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
            if distance(from: center, to: frame) < radius {
                return false
            }
            progress += 0.0025
        }
        return true
    }

    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let deltaX = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let deltaY = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }

    private static func metrics(
        width: CGFloat, height: CGFloat, content: LockTextContent, compact: Bool, scale: Double
    ) -> LockTextLayout {
        let (clock, period, headline, line) = (
            content.clock, content.period, content.headline, content.line
        )
        let full = min(width * 0.15, height * 0.26)
        let clockSize = (compact ? full * 0.24 : full) * scale
        let headlineBase = min(width * 0.042, height * 0.075)
        let headlineSize = (compact ? headlineBase * 0.55 : headlineBase) * scale
        let lineSize = max(13, width * 0.0175 * scale)
        let periodWidth = period.map { CGFloat($0.count) * 0.72 * clockSize * 0.28 } ?? 0
        let clockWidth = CGFloat(clock.count) * 0.62 * clockSize + periodWidth + clockSize * 0.06
        let headlineWidth = CGFloat(headline.count) * 0.56 * headlineSize
        let lineWidth = line.map { CGFloat($0.count) * 0.55 * lineSize + lineSize * 1.6 } ?? 0
        let blockWidth = min(width * 0.92, max(clockWidth, headlineWidth, lineWidth))
        let clockHeight = clockSize * 1.02
        let headlineHeight = headlineSize * 1.3
        let lineHeight = line == nil || compact ? 0 : lineSize * 1.5
        let clockGap = compact ? CGFloat(4) : height * 0.03 * scale
        let lineGap = lineHeight == 0 ? 0 : height * 0.03 * scale
        let blockHeight = clockHeight + clockGap + headlineHeight + lineGap + lineHeight
        return LockTextLayout(
            block: CGRect(x: 0, y: 0, width: blockWidth, height: blockHeight),
            clockSize: clockSize, headlineSize: headlineSize, lineSize: lineSize,
            clockHeight: clockHeight, headlineHeight: headlineHeight, lineHeight: lineHeight,
            clockGap: clockGap, lineGap: lineGap
        )
    }
}
