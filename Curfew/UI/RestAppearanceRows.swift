import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// The theme editor's words: the names of the palettes, clock faces and
/// moments, kept together so rows and the spoken preview say the same thing.
enum RestAppearanceCopy {
    static func paletteName(_ palette: RestAppearancePreferences.Palette) -> String {
        switch palette {
        case .sundown: "Sundown"
        case .warmAmber: "Desert"
        case .coolTwilight: "Polar"
        }
    }

    static func paletteSummary(_ palette: RestAppearancePreferences.Palette) -> String {
        switch palette {
        case .sundown: "Clear blue days, gold evenings, an indigo night."
        case .warmAmber: "Dusty days, terracotta evenings, a warm dark night."
        case .coolTwilight: "Cold teal days, rose evenings, a green-blue night."
        }
    }

    static func backgroundName(_ background: RestAppearancePreferences.Background) -> String {
        switch background {
        case .atmosphere: "The sky"
        case .solid: "A solid color"
        case .image: "Your own image"
        }
    }

    static func clockName(_ style: RestAppearancePreferences.ClockStyle) -> String {
        switch style {
        case .rounded: "Rounded"
        case .standard: "Standard"
        case .serif: "Serif"
        }
    }

    static func positionName(_ position: RestAppearancePreferences.ClockPosition) -> String {
        switch position {
        case .center: "Center"
        case .upperCenter: "Top"
        case .lowerLeft: "Lower left"
        }
    }

    static func positionPhrase(_ position: RestAppearancePreferences.ClockPosition) -> String {
        switch position {
        case .center: "in the center"
        case .upperCenter: "at the top"
        case .lowerLeft: "in the lower left"
        }
    }

    /// The moment a line is said, in plain words.
    static func moment(_ line: VoicePack.Line) -> String {
        switch line {
        case .lockedHeadline: "On the lock"
        case .thirtyMinutes: "30 minutes before curfew"
        case .fifteenMinutes: "15 minutes before curfew"
        case .fiveMinutes: "5 minutes before curfew"
        case .lastMinute: "In the last minute"
        case .sunriseGreeting: "Sunrise greeting"
        case .sunriseQuestion: "Sunrise question"
        case .overrideQuestion: "Asking for an override"
        }
    }
}

/// One choice in a list of choices: its words, and a checkmark when chosen.
/// The whole row is the button; VoiceOver hears it as a selected option.
struct RestAppearanceChoiceRow<Leading: View>: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: CurfewSpacing.medium) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(CurfewTheme.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: CurfewSpacing.medium)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CurfewTheme.accent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The palette's four moments side by side, day, last hour, dusk and night,
/// as narrow bands in one thumbnail, so palettes differ at a glance.
struct RestPaletteSwatch: View {
    let palette: RestAppearancePreferences.Palette

    static let size = CGSize(width: 72, height: 40)

    /// Day, the last hour, dusk and night of a 7 AM to 6 PM day.
    static let moments: [HorizonFrame] = {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return [5.5, 10.5, 11.4, 14.7].map { hours in
            HorizonMoment(
                now: start.addingTimeInterval(hours * 3600), dayStart: start,
                curfew: start.addingTimeInterval(11 * 3600),
                nextUnlock: start.addingTimeInterval(24 * 3600)
            ).frame
        }
    }()

    var body: some View {
        let band = Self.size.width / CGFloat(Self.moments.count)
        HStack(spacing: 0) {
            ForEach(Self.moments.indices, id: \.self) { index in
                // The middle of each moment's sky, where its light sits.
                HorizonStillSky(frame: Self.moments[index])
                    .frame(width: Self.size.height * 1.6, height: Self.size.height)
                    .frame(width: band, height: Self.size.height)
                    .clipped()
            }
        }
        .environment(\.horizonPalette, HorizonPalette(palette))
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(CurfewTheme.border, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// The three clock faces, each shown in its own face. Arrow keys and Tab
/// move between them; Space or Return chooses.
struct RestClockFacePicker: View {
    @Binding var selection: RestAppearancePreferences.ClockStyle

    var body: some View {
        HStack(spacing: CurfewSpacing.small) {
            ForEach(RestAppearancePreferences.ClockStyle.allCases, id: \.self) { style in
                face(style)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clock style")
    }

    private func face(_ style: RestAppearancePreferences.ClockStyle) -> some View {
        let chosen = selection == style
        let shape = RoundedRectangle(cornerRadius: CurfewRadius.control, style: .continuous)
        return Button { selection = style } label: {
            VStack(spacing: 2) {
                Text("9:41")
                    .font(.system(size: 22, weight: .semibold, design: style.fontDesign))
                    .monospacedDigit()
                Text(RestAppearanceCopy.clockName(style))
                    .font(.caption)
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
            .frame(width: 76, height: 54)
            .background(chosen ? CurfewTheme.surface : Color.clear, in: shape)
            .overlay {
                shape.strokeBorder(
                    chosen ? CurfewTheme.accent : CurfewTheme.border,
                    lineWidth: chosen ? 2 : 1
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .foregroundStyle(CurfewTheme.ink)
        .accessibilityLabel(RestAppearanceCopy.clockName(style))
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("rest-clock-style-\(style.rawValue)")
    }
}

/// One line the person can rewrite: the moment it is said, the field with
/// the voice's own words as its placeholder, and a way back to them.
struct RestOwnWordsRow: View {
    @Environment(CurfewAppModel.self) private var model
    let line: VoicePack.Line
    /// Called when the field takes focus, so the preview can show this moment.
    var onFocus: (VoicePack.Line) -> Void = { _ in }
    /// Called when the person changes whether the screen saver shows the
    /// lock's own words.
    var onSaverChange: () -> Void = {}
    @State private var text = ""
    @FocusState private var focused: Bool

    private var builtIn: String {
        VoicePack(model.restAppearance.voice).line(line)
    }

    private var isCustom: Bool {
        model.restAppearance.customLines[line] != nil
    }

    private var limit: Int {
        VoiceCustomLines.maximumLength
    }

    var body: some View {
        LabeledContent {
            VStack(alignment: .leading, spacing: CurfewSpacing.small) {
                HStack(spacing: CurfewSpacing.small) {
                    field
                    reset
                }
                if line == .lockedHeadline, isCustom {
                    saverToggle
                }
            }
        } label: {
            Text(RestAppearanceCopy.moment(line))
        }
        .onAppear { text = model.restAppearance.customLines[line] ?? "" }
        .onChange(of: text) { _, value in save(value) }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                onFocus(line)
            }
        }
    }

    /// The person's words, left to right, with the count inside the field's
    /// end as the limit nears.
    private var field: some View {
        TextField(RestAppearanceCopy.moment(line), text: $text, prompt: Text(builtIn))
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .textFieldStyle(.roundedBorder)
            .frame(width: 300)
            .overlay(alignment: .trailing) {
                if text.count >= limit - 10 {
                    Text("\(limit - text.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .padding(.trailing, CurfewSpacing.small)
                        .accessibilityLabel("\(limit - text.count) characters left")
                }
            }
            .focused($focused)
            .onSubmit { focused = false }
            .accessibilityLabel(RestAppearanceCopy.moment(line))
            .accessibilityHint("Leave empty to use “\(builtIn)”.")
            .accessibilityIdentifier("rest-own-words-\(line.rawValue)")
    }

    /// The way back to the voice's words: a small control at the row's end,
    /// there only once the line is the person's own. Its slot is kept so
    /// every field lines up.
    private var reset: some View {
        Button { text = "" } label: {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.body)
                .foregroundStyle(CurfewTheme.mutedInk)
        }
        .buttonStyle(.borderless)
        .help("Use the built-in words")
        .accessibilityLabel("Use the built-in words")
        .accessibilityIdentifier("rest-own-words-reset-\(line.rawValue)")
        .opacity(isCustom ? 1 : 0)
        .disabled(!isCustom)
        .accessibilityHidden(!isCustom)
        .frame(width: 18)
    }

    private var saverToggle: some View {
        Toggle("Show them in the screen saver", isOn: Binding(
            get: { model.restAppearance.saverMessageEnabled },
            set: { shows in
                model.updateTheme { $0.saverMessageEnabled = shows }
                onSaverChange()
            }
        ))
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("rest-saver-message")
    }

    private func save(_ value: String) {
        if value.count > limit {
            text = String(value.prefix(limit))
            return
        }
        model.updateTheme { $0.customLines = $0.customLines.setting(line, to: value) }
    }
}
