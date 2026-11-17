import CoreGraphics
import CurfewKit
import Foundation

/// The skyline punches: one hole per evening the person stopped themselves,
/// stacked in columns either side of the curfew line by how early or late
/// they stopped. Evenings the lock ended get no hole.
///
/// Real years are peaky, so the bin width (5, 10 or 15 minutes), the range
/// and how many hole columns each bin takes are chosen together so the holes
/// stay a comfortable size. The far tails gather in the edge bins.
struct JournalTimeCardSkyline: Equatable, Sendable {
    /// Evenings in one bin. Bin `b` below zero covers stops from `-b * w`
    /// down to just over `(-b - 1) * w` minutes early; bin `b` from zero up
    /// covers `b * w` to just under `(b + 1) * w` minutes past curfew.
    struct Bin: Equatable, Sendable {
        let bin: Int
        let count: Int
    }

    static let binChoices = [5, 10, 15]
    static let columnChoices = Array(1 ... 8)
    /// The axis runs at most this far either side of curfew.
    static let maxEarlyMinutes = 180
    static let maxLateMinutes = 90

    let binMinutes: Int
    /// Hole columns per bin. One unless the year is too peaky to stack.
    let columnsPerBin: Int
    /// Earliest to latest; the bins either side of zero meet at curfew.
    let bins: [Bin]
    /// Grid pitch in card units.
    let pitch: Double
    /// "1h early", or "1h+ early" when earlier evenings gathered at the edge.
    let earlyLabel: String
    let lateLabel: String
    /// The busiest bin in words: "10 to 15 minutes early".
    let spokenPeak: String?

    var holeCount: Int {
        bins.reduce(0) { $0 + $1.count }
    }

    init(records: [JournalDayRecord], format: JournalFormat) {
        let offsets = records.filter { $0.ending?.cause == .calledItADay }
            .compactMap(\.stopOffsetMinutes).sorted()
        let low = Self.percentile(offsets, 0.05)
        let high = Self.percentile(offsets, 0.95)

        var best: (score: Double, layout: Layout)?
        for columns in Self.columnChoices {
            for width in Self.binChoices {
                let layout = Layout(
                    offsets: offsets,
                    low: low,
                    high: high,
                    width: width,
                    columns: columns
                )
                if layout.pitch >= JournalTimeCardLayout.comfortablePitch {
                    best = (.infinity, layout)
                    break
                }
                if layout.pitch > best?.score ?? 0 {
                    best = (layout.pitch, layout)
                }
            }
            if best?.score == .infinity {
                break
            }
        }
        let layout = best?.layout
            ?? Layout(offsets: offsets, low: low, high: high, width: 5, columns: 1)

        self.binMinutes = layout.width
        self.columnsPerBin = layout.columns
        self.bins = layout.bins
        self.pitch = layout.pitch
        let earliest = -(layout.bins.first?.bin ?? -1) * layout.width
        let latest = ((layout.bins.last?.bin ?? 0) + 1) * layout.width
        let clippedEarly = (offsets.first ?? 0) < -earliest
        let clippedLate = (offsets.last ?? 0) >= latest
        self.earlyLabel = format.duration(earliest) + (clippedEarly ? "+" : "") + " early"
        self.lateLabel = format.duration(latest) + (clippedLate ? "+" : "") + " over"
        let edges = (first: layout.bins.first?.bin, last: layout.bins.last?.bin)
        self.spokenPeak = layout.bins.filter { $0.count >= 1 }
            .max { ($0.count, -abs($0.bin)) < ($1.count, -abs($1.bin)) }
            .map { peak in
                Self.words(
                    bin: peak.bin, width: layout.width,
                    isEdge: (peak.bin == edges.first && clippedEarly)
                        || (peak.bin == edges.last && clippedLate)
                )
            }
    }

    // MARK: Geometry, in card units

    /// The pattern's width and height: whole hole columns and the tallest
    /// stack.
    var patternSize: CGSize {
        let tallest = bins.map { ($0.count + columnsPerBin - 1) / columnsPerBin }.max() ?? 0
        return CGSize(
            width: Double(bins.count * columnsPerBin + 1) * pitch,
            height: Double(tallest) * pitch
        )
    }

    /// Top left of the pattern: centred across the content width, standing
    /// on the skyline's base. One empty column, the gutter, holds the curfew
    /// line between the early and late bins.
    var patternOrigin: CGPoint {
        let size = patternSize
        return CGPoint(
            x: JournalTimeCardLayout.margin + (JournalTimeCardLayout.contentWidth - size.width) / 2,
            y: JournalTimeCardLayout.skylineHoleBottom - size.height
        )
    }

    /// Where the curfew line runs: between the last early bin and the first
    /// late one.
    var curfewX: Double {
        let early = bins.count { $0.bin < 0 }
        return patternOrigin.x + (Double(early * columnsPerBin) + 0.5) * pitch
    }

    var holes: [JournalTimeCardHole] {
        let origin = patternOrigin
        let radius = pitch * JournalTimeCardLayout.holeShare / 2
        var holes: [JournalTimeCardHole] = []
        for (index, bin) in bins.enumerated() {
            for hole in 0 ..< bin.count {
                let column = index * columnsPerBin + hole % columnsPerBin + (bin.bin < 0 ? 0 : 1)
                let row = hole / columnsPerBin
                holes.append(JournalTimeCardHole(
                    centerX: origin.x + (Double(column) + 0.5) * pitch,
                    centerY: JournalTimeCardLayout.skylineHoleBottom - (Double(row) + 0.5) * pitch,
                    radius: radius
                ))
            }
        }
        return holes
    }

    // MARK: Choosing the bins

    /// One way to bin the year: a width, the bins from the trimmed range,
    /// and the pitch it allows.
    private struct Layout {
        let width: Int
        let columns: Int
        let bins: [Bin]
        let pitch: Double

        init(offsets: [Int], low: Int, high: Int, width: Int, columns: Int) {
            self.width = width
            self.columns = columns
            // At least one bin either side of curfew, at most the axis's reach.
            let lowest = max(Self.bin(min(low, -1), width: width), -maxEarlyMinutes / width)
            let highest = min(Self.bin(max(high, 0), width: width), maxLateMinutes / width - 1)
            var counts = [Int](repeating: 0, count: highest - lowest + 1)
            for offset in offsets {
                let bin = min(max(Self.bin(offset, width: width), lowest), highest)
                counts[bin - lowest] += 1
            }
            self.bins = counts.enumerated().map { Bin(bin: lowest + $0.offset, count: $0.element) }
            let stacks = counts.map { ($0 + columns - 1) / columns }.max() ?? 0
            let across = JournalTimeCardLayout.contentWidth / Double(counts.count * columns + 1)
            let tall = JournalTimeCardLayout.skylineHoleHeight / Double(max(stacks, 1))
            self.pitch = min(across, tall, JournalTimeCardLayout.maximumPitch)
        }

        static func bin(_ offset: Int, width: Int) -> Int {
            offset < 0 ? -Int((Double(-offset) / Double(width)).rounded(.up)) : offset / width
        }
    }

    /// Nearest-rank percentile of sorted values; 0 when there are none.
    private static func percentile(_ sorted: [Int], _ share: Double) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((share * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    private static func words(bin: Int, width: Int, isEdge: Bool) -> String {
        if bin < 0 {
            let far = -bin * width
            return isEdge ? "\(far) minutes or more early" : "\(far - width) to \(far) minutes early"
        }
        let near = bin * width
        if isEdge {
            return "\(near) minutes or more over"
        }
        return bin == 0 ? "at curfew or up to \(width) minutes over"
            : "\(near) to \(near + width) minutes over"
    }
}
