import SwiftUI

// Settings layout rules, enforced by these components so no pane lays out
// help text by hand:
// 1. Text that explains one control is that row's `detail`, directly under
//    its label in secondary text; the control aligns with the label's first
//    line.
// 2. Text that explains the whole group is the group's `footer`, under the box.
// 3. Help text is never a row of its own. Dividers separate controls only.
// 4. Live status is the `detail` of the row it is about. A warning that needs
//    an action is one `SettingsActionRow` with `tone: .warning`.
// 5. Rows share one height and inset; icon-led rows are not mixed in.

/// How a row's secondary line reads.
enum SettingsDetailTone {
    case secondary
    case warning
}

/// A titled box of rows with an optional explanatory footer under it.
struct SettingsGroup<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            if let title {
                Text(title)
                    .font(CurfewTypography.bodyEmphasis(13))
                    .foregroundStyle(CurfewTheme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
        } footer: {
            if let footer {
                Text(footer)
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The label column every row shares: a title and an optional secondary line.
struct SettingsRowLabel: View {
    let title: String
    var detail: String?
    var tone: SettingsDetailTone = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(tone == .warning ? CurfewTheme.warning : CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One settings row: label and secondary line on the left, the control on the
/// right, aligned with the label's first line.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    var tone: SettingsDetailTone = .secondary
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            SettingsRowLabel(title: title, detail: detail, tone: tone)
            control
                .fixedSize()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }
}

/// A button that belongs to a row's own control, such as withdrawing the
/// waiting change that row's detail describes.
struct SettingsRowAction {
    let title: String
    var accessibilityLabel: String?
    let perform: () -> Void
}

/// A row whose control is a number with a stepper.
///
/// `shownValue` lets the number differ from what the stepper edits: a weekly
/// limit shows the value in force while the stepper moves the waiting raise,
/// which the row's `detail` then describes. `action` sits beside the stepper
/// so the way out of that status stays with its control.
struct SettingsValueRow: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var detail: String?
    var tone: SettingsDetailTone = .secondary
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var usesMinutes = false
    var accessibilityTitle: String?
    var shownValue: Int?
    var action: SettingsRowAction?

    init(
        title: String, detail: String? = nil, tone: SettingsDetailTone = .secondary,
        value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, usesMinutes: Bool = false,
        accessibilityTitle: String? = nil, shownValue: Int? = nil, action: SettingsRowAction? = nil
    ) {
        self.title = title
        self.detail = detail
        self.tone = tone
        _value = value
        self.range = range
        self.step = step
        self.usesMinutes = usesMinutes
        self.accessibilityTitle = accessibilityTitle
        self.shownValue = shownValue
        self.action = action
    }

    private func label(_ number: Int) -> String {
        usesMinutes ? String(localized: "\(number) min") : number.formatted()
    }

    var body: some View {
        SettingsRow(title: title, detail: detail, tone: tone) {
            HStack(spacing: 6) {
                if let action {
                    Button(action.title, action: action.perform)
                        .buttonStyle(CurfewLinkButtonStyle())
                        .accessibilityLabel(Text(action.accessibilityLabel ?? action.title))
                        .padding(.trailing, 6)
                }
                Text(label(shownValue ?? value))
                    .font(CurfewTypography.bodyEmphasis(13))
                    .monospacedDigit()
                    .frame(minWidth: 62)
                    .padding(.vertical, 4)
                    .background(CurfewTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
                    .accessibilityLabel(Text(LocalizedStringKey(accessibilityTitle ?? title)))
                    .accessibilityValue(label(value))
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// A row whose control is a switch.
struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    var tone: SettingsDetailTone = .secondary
    var identifier: String?
    @Binding var isOn: Bool

    init(
        title: String, detail: String? = nil, tone: SettingsDetailTone = .secondary,
        identifier: String? = nil, isOn: Binding<Bool>
    ) {
        self.title = title
        self.detail = detail
        self.tone = tone
        self.identifier = identifier
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title: title, detail: detail, tone: tone) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(Text(LocalizedStringKey(title)))
                .accessibilityIdentifier(identifier ?? title)
        }
    }
}

/// A row whose control is a button. With `tone: .warning` it is the one row a
/// problem gets: the message and the way forward together. A `nil` action
/// title leaves a status row with nothing to press.
struct SettingsActionRow: View {
    let title: String
    var detail: String?
    var tone: SettingsDetailTone = .secondary
    let actionTitle: String?
    var identifier: String?
    let action: () -> Void

    init(
        title: String, detail: String? = nil, tone: SettingsDetailTone = .secondary,
        actionTitle: String?, identifier: String? = nil, action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.detail = detail
        self.tone = tone
        self.actionTitle = actionTitle
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        SettingsRow(title: title, detail: detail, tone: tone) {
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(CurfewSecondaryButtonStyle())
                    .accessibilityIdentifier(identifier ?? actionTitle)
            }
        }
    }
}

/// A row whose control is a menu or segmented picker.
struct SettingsPickerRow<Value: Hashable, Options: View>: View {
    let title: String
    var detail: String?
    @Binding var selection: Value
    var segmented = false
    var identifier: String?
    @ViewBuilder var options: Options

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            if segmented {
                Picker(title, selection: $selection) { options }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(identifier ?? title)
            } else {
                Picker(title, selection: $selection) { options }
                    .labelsHidden()
                    .accessibilityIdentifier(identifier ?? title)
            }
        }
    }
}
