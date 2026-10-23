import SwiftUI

/// Native controls share a trailing column so labels remain easy to scan.
struct SettingsValueRow: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var usesMinutes = false
    var accessibilityTitle: String?

    private var valueLabel: String {
        usesMinutes ? String(localized: "\(value) min") : value.formatted()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(title))
                .font(CurfewTypography.body(13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(valueLabel)
                .font(CurfewTypography.bodyEmphasis(13))
                .monospacedDigit()
                .frame(minWidth: 62)
                .padding(.vertical, 6)
                .background(CurfewTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 7))
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(Text(LocalizedStringKey(accessibilityTitle ?? title)))
                .accessibilityValue(valueLabel)
        }
        .padding(.vertical, 2)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(title))
                .font(CurfewTypography.bodyEmphasis(13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel(Text(LocalizedStringKey(title)))
        }
        .padding(.vertical, 4)
    }
}
