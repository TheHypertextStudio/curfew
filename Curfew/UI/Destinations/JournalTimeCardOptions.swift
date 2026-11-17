import CurfewAtmosphere
import SwiftUI

/// The editing panel beside the card: four labelled rows, a segmented
/// control for each choice and colour swatches for the sky, then Shuffle and
/// Done. The big card is the only preview; it changes as each option does.
struct JournalTimeCardOptions: View {
    let style: JournalTimeCardStyle
    let choose: ((inout JournalTimeCardChoices) -> Void) -> Void
    let shuffle: () -> Void
    let done: () -> Void

    /// Every control is this wide, so their edges line up.
    static let controlWidth: CGFloat = 312
    /// Every control is this tall: the large segmented control's height.
    static let controlHeight: CGFloat = 34

    var body: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: CurfewSpacing.large,
            verticalSpacing: CurfewSpacing.medium
        ) {
            row("Stock") {
                segmented("Stock", JournalTimeCardStock.allCases, current: style.stock) { option in
                    choose { $0.stock = option }
                }
            }
            row("Sky") {
                JournalTimeCardSegmented(
                    title: "Sky",
                    options: JournalTimeCardSky.allCases,
                    current: style.sky,
                    pick: { option in choose { $0.sky = option } },
                    leading: { sky in
                        JournalTimeCardSkySwatch(sky: sky, isSelected: sky == style.sky)
                    }
                )
            }
            row("Punches") {
                segmented(
                    "Punches",
                    JournalTimeCardPunches.allCases,
                    current: style.punches
                ) { option in
                    choose { $0.punches = option }
                }
            }
            row("Headline") {
                segmented(
                    "Headline",
                    JournalTimeCardHeadline.allCases,
                    current: style.headline
                ) { option in
                    choose { $0.headline = option }
                }
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                actions
                    .padding(.top, CurfewSpacing.small)
            }
        }
        .padding(CurfewSpacing.xLarge)
        .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: CurfewRadius.panel, style: .continuous)
        )
        .fixedSize()
    }

    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        GridRow(alignment: .center) {
            Text(title)
                .journalFont(.cardTitle)
                .foregroundStyle(JournalStyle.ink)
                .accessibilityHidden(true)
            control()
                .frame(width: Self.controlWidth, height: Self.controlHeight)
        }
    }

    private func segmented<Option: Hashable & JournalTimeCardTitled>(
        _ title: String,
        _ options: [Option],
        current: Option,
        pick: @escaping (Option) -> Void
    ) -> some View {
        JournalTimeCardSegmented(
            title: title,
            options: options,
            current: current,
            pick: pick
        ) { _ in
            EmptyView()
        }
    }

    /// Shuffle and Done, splitting the controls' width between them.
    private var actions: some View {
        HStack(spacing: CurfewSpacing.small) {
            Button(action: shuffle) {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(JournalTimeCardActionStyle())
            .help("Try a random card")
            Button(action: done) {
                Label("Done", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(JournalTimeCardActionStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
        }
        .labelStyle(.titleAndIcon)
        .frame(width: Self.controlWidth)
    }
}

/// The choices that show a title in the editor.
protocol JournalTimeCardTitled {
    var title: String { get }
}

extension JournalTimeCardStock: JournalTimeCardTitled {}
extension JournalTimeCardSky: JournalTimeCardTitled {}
extension JournalTimeCardPunches: JournalTimeCardTitled {}
extension JournalTimeCardHeadline: JournalTimeCardTitled {}

/// One choice as equal segments in a capsule track, the chosen one raised.
/// Every row of the editor uses it, so all four share one width and height.
/// `leading` draws an optional mark before each title, such as a sky swatch.
struct JournalTimeCardSegmented<Option: Hashable & JournalTimeCardTitled, Leading: View>: View {
    let title: String
    let options: [Option]
    let current: Option
    let pick: (Option) -> Void
    @ViewBuilder var leading: (Option) -> Leading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.07), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option == current
        return Button { pick(option) } label: {
            HStack(spacing: CurfewSpacing.small) {
                leading(option)
                Text(option.title)
                    .journalFont(.row)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundStyle(isSelected ? JournalStyle.ink : JournalStyle.soft)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white)
                        .shadow(
                            color: .black.opacity(colorScheme == .dark ? 0 : 0.14),
                            radius: 1.5,
                            y: 0.5
                        )
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: current)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A small disc of one sky's dusk, far sky at the top and the light at the
/// bottom, ringed when it is the chosen sky.
struct JournalTimeCardSkySwatch: View {
    let sky: JournalTimeCardSky
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(LinearGradient(
                colors: sky.swatchStops.map(SundownPalette.TimeCard.color),
                startPoint: .top,
                endPoint: .bottom
            ))
            .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
            .frame(width: 14, height: 14)
            .padding(2)
            .overlay {
                Circle().strokeBorder(CurfewTheme.accent, lineWidth: 1.5)
                    .opacity(isSelected ? 1 : 0)
            }
            .accessibilityHidden(true)
    }
}
