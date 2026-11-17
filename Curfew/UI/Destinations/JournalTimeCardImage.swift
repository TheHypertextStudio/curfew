import AppKit
import CurfewAtmosphere
import SwiftUI
import UniformTypeIdentifiers

/// The time card as a PNG, for Share, drag, Copy and Save: the card on its
/// stage at 4:5. The sky comes from the CPU reference renderer at the
/// export size, so the image is the same on every Mac and in either
/// appearance, and it matches the card the person sees.
struct JournalYearReviewImage: Transferable {
    let card: JournalYearReview.Card
    let style: JournalTimeCardStyle

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { image in
            try await image.pngData()
        }
        .suggestedFileName { $0.card.fileName }
    }

    enum RenderError: LocalizedError {
        case failed

        var errorDescription: String? {
            "Curfew could not draw the time card."
        }
    }

    /// Renders the card on its stage at ``JournalYearReview/exportSize``.
    @MainActor
    func pngData() async throws -> Data {
        let scale = JournalYearReview.exportScale
        let width = JournalYearReview.exportCardWidth
        let unit = width / JournalTimeCardLayout.size.width
        let pixelWidth = Int(width * scale)
        let pixelHeight = Int(JournalTimeCardArt<EmptyView>.skySceneHeight * unit * scale)
        let palette = style.sky.palette
        let sky = await Task.detached(priority: .userInitiated) {
            HorizonRenderer.image(
                frame: JournalTimeCardArt<EmptyView>.skyFrame, bandPhase: HorizonBandPhase.resting,
                pixelWidth: pixelWidth, pixelHeight: pixelHeight, palette: palette
            )
        }.value
        guard let sky else { throw RenderError.failed }
        let renderer = ImageRenderer(content: Self.art(card: card, style: style, sky: sky))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(JournalYearReview.exportSize)
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(
                  using: .png,
                  properties: [:]
              )
        else { throw RenderError.failed }
        return png
    }

    /// The exported picture: the card centred on its stage.
    @MainActor
    static func art(
        card: JournalYearReview.Card,
        style: JournalTimeCardStyle,
        sky: CGImage
    ) -> some View {
        JournalTimeCardArt(card: card, style: style) {
            Image(decorative: sky, scale: JournalYearReview.exportScale)
                .resizable()
                .interpolation(.none)
        }
        .frame(width: JournalYearReview.exportCardWidth)
        .frame(
            width: JournalYearReview.exportSize.width,
            height: JournalYearReview.exportSize.height
        )
        .background(JournalTimeCardInk(style).stage)
        .environment(\.dynamicTypeSize, .large)
    }
}
