import SwiftUI

/// A quiet line on Today when the Shortcut picked for after Sunrise did not
/// run. Shown on Today's next appearance and gone once Today closes or the
/// person dismisses it; never a modal.
struct SunriseShortcutNotice: View {
    @Environment(CurfewAppModel.self) private var model

    var body: some View {
        if let notice = model.sunriseShortcutNotice {
            HStack(spacing: CurfewSpacing.small) {
                Label(notice, horizonSymbol: .sunrise)
                    .sundownFont(.label, size: 13)
                Button {
                    model.dismissSunriseShortcutNotice()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .foregroundStyle(SundownPalette.supportingText)
            .padding(.bottom, CurfewSpacing.large)
            .onDisappear { model.dismissSunriseShortcutNotice() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sunrise-shortcut-notice")
        }
    }
}
