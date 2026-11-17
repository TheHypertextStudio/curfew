import AppKit
import CurfewAtmosphere
import CurfewKit
import SwiftUI
import UniformTypeIdentifiers

/// The year time card on the year page: the card on its own stage with
/// Customize and Share, or one line when the year has too few days.
struct JournalYearReviewView: View {
    let review: JournalYearReview

    var body: some View {
        switch review.content {
        case .tooFewDays(let line):
            Text(line)
                .journalFont(.row)
                .foregroundStyle(JournalStyle.soft)
                .fixedSize(horizontal: false, vertical: true)
        case .card(let card):
            JournalTimeCardStage(card: card)
        }
    }
}

/// The stage: a surface that contrasts with the card's stock, the card
/// floating on it, and two actions under it. Customize turns the stage into
/// an editing state in place, like editing a widget: the card settles and a
/// gallery of live miniatures appears under the actions.
struct JournalTimeCardStage: View {
    let card: JournalYearReview.Card
    /// Draws the hover lift without a pointer, for snapshots.
    var showsLift = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizonPalette) private var palette
    @Environment(\.journalTimeCardStore) private var store
    @State private var choices = JournalTimeCardChoices()
    @State private var hasLoaded = false
    @State private var isCustomizing: Bool
    @State private var isHovered = false
    /// Bumped on every pick so the card gives a small press.
    @State private var picks = 0

    /// The card's width on the stage.
    static let cardWidth: CGFloat = 340

    init(card: JournalYearReview.Card, showsLift: Bool = false, isCustomizing: Bool = false) {
        self.card = card
        self.showsLift = showsLift
        _isCustomizing = State(initialValue: isCustomizing)
    }

    private var style: JournalTimeCardStyle {
        choices.resolved(colorScheme: colorScheme, appSky: JournalTimeCardSky(palette: palette))
    }

    private var ink: JournalTimeCardInk {
        JournalTimeCardInk(style)
    }

    private var isLifted: Bool {
        (isHovered || showsLift) && !isCustomizing && !reduceMotion
    }

    private var image: JournalYearReviewImage {
        JournalYearReviewImage(card: card, style: style)
    }

    var body: some View {
        VStack(spacing: CurfewSpacing.xLarge) {
            cardObject
            actions
            if isCustomizing {
                JournalTimeCardGallery(card: card, style: style, choose: choose)
                    .transition(
                        reduceMotion ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                            .combined(with: .scale(scale: 0.98, anchor: .top))
                    )
            }
        }
        .padding(.horizontal, CurfewSpacing.xLarge)
        .padding(.top, CurfewSpacing.xxLarge)
        .padding(.bottom, CurfewSpacing.xLarge)
        .frame(maxWidth: .infinity)
        .background(
            ink.stage,
            in: RoundedRectangle(cornerRadius: CurfewRadius.panel, style: .continuous)
        )
        .environment(\.colorScheme, ink.stageIsDark ? .dark : .light)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: style)
        .onExitCommand {
            if isCustomizing {
                setCustomizing(false)
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            choices = store.load()
        }
    }

    // MARK: - The card

    private var cardObject: some View {
        pressable
            .scaleEffect(isCustomizing ? 0.97 : isLifted ? 1.012 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.3), value: isLifted)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .draggable(image)
            .contextMenu {
                Button { copy() } label: { Label("Copy image", systemImage: "doc.on.doc") }
                Button { save() } label: {
                    Label("Save image…", systemImage: "square.and.arrow.down")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time card")
            .accessibilityValue(card.spokenSummary(style))
            .accessibilityAddTraits(.isImage)
            .accessibilityAction(named: "Copy image") { copy() }
            .accessibilityAction(named: "Save image") { save() }
            .accessibilityAction(named: isCustomizing ? "Done" : "Customize") {
                setCustomizing(!isCustomizing)
            }
    }

    /// The card, which gives a small press each time a pick lands: down a
    /// touch, then springing back, like a card going through a clock.
    private var pressable: some View {
        JournalTimeCardArt(card: card, style: style, lift: isLifted ? 1 : 0)
            .id(style)
            .transition(.opacity)
            .frame(width: Self.cardWidth)
            .keyframeAnimator(initialValue: 1.0, trigger: picks) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                CubicKeyframe(0.965, duration: 0.09)
                SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
            }
    }

    private var preview: SharePreview<Never, Image> {
        SharePreview("Curfew time card, \(card.yearLabel)", icon: HorizonSymbol.curfew.image)
    }

    // MARK: - Actions

    private static let actionWidth: CGFloat = 116

    private var actions: some View {
        HStack(spacing: CurfewSpacing.small) {
            if isCustomizing {
                Button(action: shuffle) {
                    Label("Shuffle", systemImage: "shuffle")
                        .frame(minWidth: Self.actionWidth)
                }
                .buttonStyle(JournalTimeCardActionStyle())
                .help("Try a random card")
                Button { setCustomizing(false) } label: {
                    Label("Done", systemImage: "checkmark")
                        .frame(minWidth: Self.actionWidth)
                }
                .buttonStyle(JournalTimeCardActionStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            } else {
                Button { setCustomizing(true) } label: {
                    Label("Customize", systemImage: "paintbrush.pointed")
                        .frame(minWidth: Self.actionWidth)
                }
                .buttonStyle(JournalTimeCardActionStyle())
                .help("Choose the stock, sky, punches and headline")
                ShareLink(item: image, preview: preview) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(minWidth: Self.actionWidth)
                }
                .buttonStyle(JournalTimeCardActionStyle(prominent: true))
                .help("Share the time card as an image")
            }
        }
        .labelStyle(.titleAndIcon)
        .fixedSize()
    }

    private func setCustomizing(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.18)) {
            isCustomizing = value
        }
    }

    private func choose(_ change: (inout JournalTimeCardChoices) -> Void) {
        var next = choices
        change(&next)
        guard next != choices else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            choices = next
        }
        store.save(next)
        if !reduceMotion {
            picks += 1
        }
    }

    private func shuffle() {
        var generator = SystemRandomNumberGenerator()
        let next = JournalTimeCardChoices.shuffled(from: style, using: &generator)
        choose { $0 = next }
    }

    private func copy() {
        let image = image
        Task { @MainActor in
            do {
                try await JournalYearReviewPasteboard.write(png: image.pngData(), to: .general)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    private func save() {
        let image = image
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = card.fileName
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try await image.pngData().write(to: url)
                } catch {
                    NSApp.presentError(error)
                }
            }
        }
    }
}

/// The stage's two actions: system Liquid Glass at one control size, the
/// prominent one tinted ember. Under Reduce Transparency they are solid
/// capsules that follow the stage, light or dark.
struct JournalTimeCardActionStyle: PrimitiveButtonStyle {
    var prominent = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if !reduceTransparency {
                if prominent {
                    Button(configuration).buttonStyle(.glassProminent).tint(CurfewTheme.accentFill)
                } else {
                    Button(configuration).buttonStyle(.glass)
                }
            } else {
                Button(configuration)
                    .buttonStyle(.plain)
                    .padding(.horizontal, CurfewSpacing.large)
                    .padding(.vertical, CurfewSpacing.small + 1)
                    .background(
                        prominent ? AnyShapeStyle(CurfewTheme.accentFill)
                            : AnyShapeStyle(Color.primary.opacity(0.1)),
                        in: Capsule()
                    )
                    .foregroundStyle(prominent ? AnyShapeStyle(CurfewTheme.onAccent)
                        : AnyShapeStyle(.primary))
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .journalFont(.button)
    }
}
