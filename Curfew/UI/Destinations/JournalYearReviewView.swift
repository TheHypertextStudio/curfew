import AppKit
import CurfewAtmosphere
import CurfewKit
import SwiftUI
import UniformTypeIdentifiers

/// The year in review on the year page: the card as an object on its own
/// stage, with Share first and Copy and Save beside it, or one line when the
/// year has too few days.
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
            JournalYearReviewStage(card: card)
        }
    }
}

/// The stage: a quiet surface with the card floating in its centre and the
/// sharing actions beneath it.
struct JournalYearReviewStage: View {
    let card: JournalYearReview.Card
    /// Draws the hover lift without a pointer, for snapshots.
    var showsLift = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var work = JournalYearReviewWork.idle

    /// Widest the card grows, so it reads as an object rather than a banner.
    static let cardMaxWidth: CGFloat = 720

    private var image: JournalYearReviewImage {
        JournalYearReviewImage(card: card)
    }

    private var isLifted: Bool {
        (isHovered || showsLift) && !reduceMotion
    }

    var body: some View {
        VStack(spacing: CurfewSpacing.xLarge) {
            cardObject
            actions
        }
        .padding(.horizontal, CurfewSpacing.xLarge)
        .padding(.top, CurfewSpacing.xxLarge)
        .padding(.bottom, CurfewSpacing.xLarge + CurfewSpacing.xSmall)
        .frame(maxWidth: .infinity)
        .background(
            JournalStyle.stage,
            in: RoundedRectangle(cornerRadius: CurfewRadius.panel, style: .continuous)
        )
    }

    // MARK: - The card

    private var cardObject: some View {
        let shape = RoundedRectangle(cornerRadius: CurfewRadius.panel, style: .continuous)
        return JournalYearReviewArt(card: card) {
            HorizonSkyView(frame: JournalYearReview.skyFrame, isDayRunning: false)
        }
        .aspectRatio(JournalYearReview.aspectRatio, contentMode: .fit)
        .clipShape(shape)
        .contentShape(shape)
        .background {
            // The shadows sit on a filled copy of the shape so they follow
            // its continuous corners.
            shape.fill(SundownPalette.nightSky)
                .shadow(
                    color: JournalStyle.cardContactShadow,
                    radius: isLifted ? 4 : 2,
                    y: isLifted ? 3 : 1.5
                )
                .shadow(
                    color: JournalStyle.cardAmbientShadow,
                    radius: isLifted ? 40 : 26,
                    y: isLifted ? 26 : 16
                )
        }
        .frame(maxWidth: Self.cardMaxWidth)
        .scaleEffect(isLifted ? 1.012 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isLifted)
        .onHover { isHovered = $0 }
        .draggable(image)
        .contextMenu {
            ShareLink(item: image, preview: preview) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button { copy() } label: {
                Label("Copy image", systemImage: "doc.on.doc")
            }
            .disabled(work.isRendering)
            Button { save() } label: {
                Label("Save image…", systemImage: "square.and.arrow.down")
            }
            .disabled(work.isRendering)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Year in review, \(card.yearLabel)")
        .accessibilityValue(card.accessibilityValue)
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: "Copy image") { copy() }
        .accessibilityAction(named: "Save image") { save() }
    }

    private var preview: SharePreview<Never, Image> {
        SharePreview("Year in review, \(card.yearLabel)", icon: HorizonSymbol.curfew.image)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: CurfewSpacing.small) {
            ShareLink(item: image, preview: preview) {
                Label("Share…", systemImage: "square.and.arrow.up")
                    .padding(.horizontal, CurfewSpacing.small)
                    .padding(.vertical, CurfewSpacing.xSmall)
            }
            .buttonStyle(CurfewPrimaryButtonStyle())
            .help("Share the year in review as an image")
            .padding(.trailing, CurfewSpacing.xSmall)
            Button { copy() } label: {
                Label(work.copyTitle, systemImage: work.copySymbol)
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
            .disabled(work.isRendering)
            .help("Copy the year in review as an image")
            Button { save() } label: {
                Label(work.saveTitle, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
            .disabled(work.isRendering)
            .help("Save the year in review as an image")
        }
        .labelStyle(.titleAndIcon)
        .fixedSize()
    }

    private func copy() {
        guard !work.isRendering else { return }
        work = .copying
        Task { @MainActor in
            do {
                let png = try await image.pngData()
                JournalYearReviewPasteboard.write(png: png, to: .general)
                work = .copied
                try? await Task.sleep(for: JournalYearReviewWork.copiedDuration)
                if work == .copied {
                    work = .idle
                }
            } catch {
                work = .idle
                NSApp.presentError(error)
            }
        }
    }

    private func save() {
        guard !work.isRendering else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = card.fileName
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                work = .saving
                defer { work = .idle }
                do {
                    try await image.pngData().write(to: url)
                } catch {
                    NSApp.presentError(error)
                }
            }
        }
    }
}

/// The card's picture: the dimmed sky, the year, the headline, the marks on
/// the curfew line and the four totals. Every size is a share of the width,
/// so the card on screen and the exported image are the same picture at two
/// sizes. It always draws in its own night colours, whatever the appearance.
struct JournalYearReviewArt<Sky: View>: View {
    let card: JournalYearReview.Card
    @ViewBuilder var sky: Sky

    /// Words and the early marks: the text colour over the sky.
    static var bone: Color {
        SundownPalette.warmWhite
    }

    /// The over marks.
    static var ember: Color {
        JournalStyle.overOnSky
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let inset = width * 0.05
            ZStack(alignment: .topLeading) {
                sky
                Color.black.opacity(JournalYearReview.skyDimming)
                marks(width: width, height: height)
                VStack(alignment: .leading, spacing: 0) {
                    Text(card.yearLabel)
                        .font(display(max(width * 0.022, 11)))
                        .kerning(-0.02 * max(width * 0.022, 11))
                        .opacity(0.9)
                        .padding(.top, height * 0.07)
                    Text(card.headline)
                        .font(display(width * 0.052))
                        .kerning(-0.02 * width * 0.052)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: width * 0.6, alignment: .leading)
                        .padding(.top, height * 0.025)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 0) {
                        totals(width: width)
                        Spacer(minLength: width * 0.02)
                        wordmark(width: width)
                    }
                    .padding(.bottom, height * 0.07)
                }
                .padding(.horizontal, inset)
                .frame(width: width, height: height, alignment: .topLeading)
            }
            .foregroundStyle(Self.bone)
        }
        .environment(\.colorScheme, .dark)
    }

    private func display(_ size: CGFloat) -> Font {
        SundownType.Role.display.font(size: size)
    }

    private func totals(width: CGFloat) -> some View {
        let figure = max(width * 0.028, 13)
        let label = max(width * 0.0145, 9)
        return HStack(alignment: .bottom, spacing: width * 0.04) {
            ForEach(card.totals, id: \.self) { total in
                VStack(alignment: .leading, spacing: width * 0.002) {
                    Text(total.value)
                        .font(display(figure))
                        .kerning(-0.02 * figure)
                        .monospacedDigit()
                    Text(total.label)
                        .font(SundownType.Role.label.font(size: label))
                        .opacity(0.95)
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
    }

    private func wordmark(width: CGFloat) -> some View {
        let size = max(width * 0.019, 10)
        return HStack(spacing: size * 0.45) {
            Self.glyph
                .frame(width: size * 1.4, height: size * 1.1)
            Text("Curfew")
                .font(display(size))
                .kerning(-0.02 * size)
        }
    }

    /// Curfew's mark: the sun resting on the line, as in the menu bar.
    private static var glyph: some View {
        Canvas { context, size in
            // The prototype's 22 by 18 canvas, y down.
            let unit = min(size.width / 22, size.height / 18)
            let lineY = HorizonMenuBarGlyph.lineY * unit
            var sun = context
            sun.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: lineY - 0.9 * unit)))
            sun.fill(
                Path(ellipseIn: CGRect(
                    x: 7 * unit,
                    y: 6 * unit,
                    width: 8 * unit,
                    height: 8 * unit
                )),
                with: .color(bone)
            )
            var line = Path()
            line.move(to: CGPoint(x: 2 * unit, y: lineY))
            line.addLine(to: CGPoint(x: 20 * unit, y: lineY))
            context.stroke(
                line, with: .color(bone),
                style: StrokeStyle(lineWidth: 1.8 * unit, lineCap: .round)
            )
        }
        .accessibilityHidden(true)
    }

    private func marks(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, _ in
            let stroke = JournalYearMark.strokeWidth(count: card.marks.count, width: width)
            for mark in card.marks {
                var path = Path()
                path.move(to: CGPoint(x: mark.centerX * width, y: mark.top * height))
                path.addLine(to: CGPoint(x: mark.centerX * width, y: mark.bottom * height))
                let color: Color = switch mark.kind {
                case .early: Self.bone.opacity(0.95)
                case .atCurfew: Self.bone.opacity(0.5)
                case .over: Self.ember
                }
                context.stroke(
                    path, with: .color(color),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
            }
            var line = Path()
            let lineY = JournalYearMark.lineY * height
            line.move(to: CGPoint(x: JournalYearMark.lineStart * width, y: lineY))
            line.addLine(to: CGPoint(x: JournalYearMark.lineEnd * width, y: lineY))
            context.stroke(
                line, with: .color(Self.bone.opacity(0.9)),
                style: StrokeStyle(lineWidth: max(1, width * 0.0016), lineCap: .round)
            )
        }
        .accessibilityHidden(true)
    }
}

/// The year in review as a PNG, for Save and Share. The sky comes from the
/// CPU reference renderer at the fixed export size, so the image is the same
/// on every Mac and in either appearance.
struct JournalYearReviewImage: Transferable {
    let card: JournalYearReview.Card

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { image in
            try await image.pngData()
        }
        .suggestedFileName { $0.card.fileName }
    }

    enum RenderError: LocalizedError {
        case failed

        var errorDescription: String? {
            "Curfew could not draw the year in review."
        }
    }

    /// Renders the card at ``JournalYearReview/exportSize``.
    @MainActor
    func pngData() async throws -> Data {
        let size = JournalYearReview.exportSize
        let scale = JournalYearReview.exportScale
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        let sky = await Task.detached(priority: .userInitiated) {
            HorizonRenderer.image(
                frame: JournalYearReview.skyFrame, bandPhase: HorizonBandPhase.resting,
                pixelWidth: pixelWidth, pixelHeight: pixelHeight
            )
        }.value
        guard let sky else { throw RenderError.failed }
        let renderer = ImageRenderer(content: Self.art(card: card, sky: sky))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(
                  using: .png,
                  properties: [:]
              )
        else { throw RenderError.failed }
        return png
    }

    /// The exported picture, laid out at the export size.
    @MainActor
    static func art(card: JournalYearReview.Card, sky: CGImage) -> some View {
        JournalYearReviewArt(card: card) {
            Image(decorative: sky, scale: JournalYearReview.exportScale)
                .resizable()
                .interpolation(.none)
        }
        .frame(
            width: JournalYearReview.exportSize.width,
            height: JournalYearReview.exportSize.height
        )
        .environment(\.dynamicTypeSize, .large)
    }
}
