import AppKit

/// The drawn menu bar icon: a sun over a line. The sun sits lower as curfew
/// nears, rests on the line in the last half hour, is absent while locked and
/// rises on the left at Sunrise. Geometry follows the prototype's menu bar
/// strip in a 22 by 18 point canvas with y down; the sun is clipped at the line.
struct HorizonMenuBarGlyph: Equatable {
    enum State: Equatable {
        case working(minutesToCurfew: Double)
        case lastHalfHour
        case locked
        case sunrise

        static func resolve(isLocked: Bool, isSunrise: Bool, minutesToCurfew: Double?) -> State {
            if isLocked {
                return .locked
            }
            if isSunrise {
                return .sunrise
            }
            guard let minutesToCurfew else { return .working(minutesToCurfew: .infinity) }
            return minutesToCurfew <= 30 ? .lastHalfHour :
                .working(minutesToCurfew: minutesToCurfew)
        }
    }

    static let canvas = CGSize(width: 22, height: 18)
    static let lineY: CGFloat = 13.5
    static let lineWidth: CGFloat = 1.6
    static let sunRadius: CGFloat = 3.5
    /// The highest the sun sits, with its top just inside the canvas.
    static let highestSun: CGFloat = 4

    var state: State

    var size: CGSize {
        Self.canvas
    }

    var lineStart: CGPoint {
        CGPoint(x: 2, y: Self.lineY)
    }

    var lineEnd: CGPoint {
        CGPoint(x: 20, y: Self.lineY)
    }

    /// Where the sun's centre is, or nil when there is no sun.
    var sunCenter: CGPoint? {
        switch state {
        case .working(let minutes):
            // Through the prototype's 6 at 150 minutes and 10 at 50 minutes.
            let height = 10 - (minutes - 50) / 25
            return CGPoint(x: 13, y: min(max(height, Self.highestSun), Self.lineY))
        case .lastHalfHour:
            return CGPoint(x: 13, y: Self.lineY)
        case .locked:
            return nil
        case .sunrise:
            return CGPoint(x: 7, y: Self.lineY)
        }
    }

    private var accessibilityDescription: String {
        switch state {
        case .working, .lastHalfHour: "Curfew"
        case .locked: "Curfew, locked"
        case .sunrise: "Curfew, Sunrise"
        }
    }

    /// A template image for the status item.
    func image() -> NSImage {
        let glyph = self
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            if let center = glyph.sunCenter {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: CGRect(x: 0, y: 0, width: glyph.size.width, height: Self.lineY))
                    .addClip()
                let radius = Self.sunRadius
                NSBezierPath(ovalIn: CGRect(
                    x: center.x - radius, y: center.y - radius, width: radius * 2,
                    height: radius * 2
                )).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            let line = NSBezierPath()
            line.move(to: glyph.lineStart)
            line.line(to: glyph.lineEnd)
            line.lineWidth = Self.lineWidth
            line.lineCapStyle = .round
            line.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
