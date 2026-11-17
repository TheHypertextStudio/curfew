import AppKit
import CoreGraphics
import CurfewAtmosphere
import CurfewKit
import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentValues {
    /// Opens "Your own words" when the pane appears, for full-size renders of
    /// the pane with its rows showing.
    @Entry var restOwnWordsInitiallyOpen = false
}

/// The Rest screen pane, the theme editor. A theme is a sky palette, a clock
/// style and a voice; the real screens sit at the top, drawn full size and
/// scaled, and every change below shows there at once and is saved as it is
/// made. There is no Apply button.
///
/// Help text follows the Settings rule: text about one control sits under
/// that control's label in the same row; text about a whole group is one
/// footer under it.
struct RestScreenSettingsView: View {
    @Environment(CurfewAppModel.self) var model
    @State var subject = RestAppearancePreviewSubject.lock
    @State private var warningStage = WarningStage.fifteenMinutes
    @State private var ownWordsOpen = false
    @State var choosingImage = false
    @State var imageError: String?
    @State var imageOperationInProgress = false
    @State private var imageTask: Task<Void, Never>?
    @Environment(\.restOwnWordsInitiallyOpen) private var ownWordsInitiallyOpen

    var body: some View {
        Group {
            previewSection
            skySection
            clockSection
            voiceSection
            RestScreenSaverSetupSection()
        }
        .onAppear { ownWordsOpen = ownWordsOpen || ownWordsInitiallyOpen }
        .onDisappear {
            imageTask?.cancel()
            imageTask = nil
        }
        .onChange(of: choosingImage) { _, presented in
            if !presented, model.restAppearance.background == .image,
               model.restAppearance.ownedImageFilename == nil {
                model.updateTheme { $0.background = .atmosphere }
            }
        }
        .fileImporter(
            isPresented: $choosingImage, allowedContentTypes: [.jpeg, .png, .heic]
        ) { result in
            imageTask = Task { await importImage(result) }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section {
            RestAppearancePreview(subject: subject, warningStage: warningStage)
                .frame(maxWidth: .infinity)
            Picker("Show", selection: $subject) {
                ForEach(RestAppearancePreviewSubject.allCases, id: \.self) { subject in
                    Text(subject.title).tag(subject)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Preview")
            .accessibilityIdentifier("rest-preview-subject")
        }
    }

    // MARK: - Sky

    private var skySection: some View {
        Section {
            ForEach(RestAppearancePreferences.Palette.allCases, id: \.self) { palette in
                RestAppearanceChoiceRow(
                    title: RestAppearanceCopy.paletteName(palette),
                    detail: RestAppearanceCopy.paletteSummary(palette),
                    isSelected: model.restAppearance.palette == palette,
                    action: { choose(palette) },
                    leading: { RestPaletteSwatch(palette: palette) }
                )
                .accessibilityIdentifier("rest-palette-\(palette.rawValue)")
            }
            backgroundRows
            Toggle(isOn: themeBinding(\.staticBackground)) {
                Text("Keep the sky still")
                Text("On the rest screen. Reduce Motion always keeps it still.")
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("rest-static-background")
        } header: {
            Text("Sky")
        } footer: {
            Text("The sky is the same on Today, the lock, Sunrise and the screen saver.")
                .font(CurfewTypography.body(12))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
    }

    @ViewBuilder
    private var backgroundRows: some View {
        let background = model.restAppearance.background
        Picker(selection: backgroundBinding) {
            ForEach(
                [RestAppearancePreferences.Background.atmosphere, .solid, .image], id: \.self
            ) { choice in
                Text(RestAppearanceCopy.backgroundName(choice)).tag(choice)
            }
        } label: {
            Text("Behind the lock")
            if let imageError {
                Text(imageError).foregroundStyle(CurfewTheme.warning)
            } else if background != .atmosphere {
                Text("Today and Sunrise keep the sky.")
            }
        }
        .pickerStyle(.menu)
        .disabled(imageOperationInProgress)
        .accessibilityIdentifier("rest-background-choice")
        if background == .solid {
            ColorPicker("Color", selection: solidColor, supportsOpacity: false)
        }
        if background == .image, model.restAppearance.ownedImageFilename != nil {
            imageRows
        }
    }

    @ViewBuilder
    private var imageRows: some View {
        LabeledContent("Image") {
            HStack {
                Button("Choose another image…") { choosingImage = true }
                Button("Remove image", role: .destructive) {
                    imageTask = Task { await removeImage() }
                }
            }
            .disabled(imageOperationInProgress)
        }
        Slider(value: themeBinding(\.focalX), in: 0 ... 1) { Text("Horizontal focus") }
        Slider(value: themeBinding(\.focalY), in: 0 ... 1) { Text("Vertical focus") }
    }

    // MARK: - Clock

    private var clockSection: some View {
        Section {
            LabeledContent {
                RestClockFacePicker(selection: Binding(
                    get: { model.restAppearance.clockStyle },
                    set: { style in
                        model.updateTheme { $0.clockStyle = style }
                        if subject == .warning {
                            subject = .lock
                        }
                    }
                ))
            } label: {
                Text("Style")
                Text("On the lock, the screen saver and Sunrise.")
            }
            Picker(selection: Binding(
                get: { model.restAppearance.clockPosition },
                set: { position in
                    model.updateTheme { $0.clockPosition = position }
                    subject = .screenSaver
                }
            )) {
                ForEach(RestAppearancePreferences.ClockPosition.allCases, id: \.self) { position in
                    Text(RestAppearanceCopy.positionName(position)).tag(position)
                }
            } label: {
                Text("Position")
                Text("In the screen saver. The lock keeps the clock centered.")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("rest-clock-position")
        } header: {
            Text("Clock")
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section {
            ForEach(RestAppearancePreferences.Voice.allCases, id: \.self) { choice in
                let pack = VoicePack(choice)
                RestAppearanceChoiceRow(
                    title: pack.name,
                    detail: "\(pack.summary) “\(pack.lockedHeadline)”",
                    isSelected: model.restAppearance.voice == choice,
                    action: { choose(choice) },
                    leading: { EmptyView() }
                )
                .accessibilityIdentifier("rest-voice-\(choice.rawValue)")
            }
            DisclosureGroup(isExpanded: $ownWordsOpen) {
                ownWordsRows
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your own words")
                    Text(ownWordsSummary)
                        .font(.subheadline)
                        .foregroundStyle(CurfewTheme.mutedInk)
                }
            }
            .accessibilityIdentifier("rest-own-words")
        } header: {
            Text("Voice")
        }
    }

    private var ownWordsRows: some View {
        ForEach(VoicePack.Line.allCases, id: \.self) { line in
            RestOwnWordsRow(
                line: line, onFocus: show, onSaverChange: { subject = .screenSaver }
            )
        }
    }

    /// Closed: what is in the person's words. Open: the rule for every line.
    private var ownWordsSummary: String {
        if ownWordsOpen {
            return "Up to \(VoiceCustomLines.maximumLength) characters each. "
                + "An empty line uses the voice's own."
        }
        let count = model.restAppearance.customLines.count
        return switch count {
        case 0: "Rewrite the lines that carry the voice."
        case 1: "1 line in your words."
        default: "\(count) lines in your words."
        }
    }
}

// MARK: - Changes

extension RestScreenSettingsView {
    /// A palette is the app's sky, so it never replaces a chosen color or
    /// image behind the lock; with one of those, the preview turns to Today.
    private func choose(_ palette: RestAppearancePreferences.Palette) {
        model.updateTheme { $0.palette = palette }
        if model.restAppearance.background != .atmosphere, subject != .sunrise {
            subject = .warning
        }
    }

    private func choose(_ voice: RestAppearancePreferences.Voice) {
        model.updateTheme { $0.voice = voice }
        if subject == .screenSaver {
            subject = .lock
        }
    }

    /// Shows the moment a rewritten line belongs to.
    private func show(_ line: VoicePack.Line) {
        subject = RestAppearancePreviewSubject(line)
        if let stage = RestAppearancePreviewSubject.stage(for: line) {
            warningStage = stage
        }
    }

    private func themeBinding<Value>(
        _ keyPath: WritableKeyPath<RestAppearanceDraft, Value>
    ) -> Binding<Value> {
        Binding(
            get: { RestAppearanceDraft(model.restAppearance)[keyPath: keyPath] },
            set: { value in model.updateTheme { $0[keyPath: keyPath] = value } }
        )
    }

    private var backgroundBinding: Binding<RestAppearancePreferences.Background> {
        Binding(
            get: { model.restAppearance.background },
            set: { background in
                imageError = nil
                if background == .image, model.restAppearance.ownedImageFilename == nil {
                    choosingImage = true
                    return
                }
                model.updateTheme { $0.background = background }
                subject = .lock
            }
        )
    }

    private var solidColor: Binding<Color> {
        Binding(
            get: {
                let value = model.restAppearance
                return AtmospherePalette.solidBackground(
                    red: value.solidRed, green: value.solidGreen, blue: value.solidBlue
                )
            },
            set: { color in
                guard let color = NSColor(color).usingColorSpace(.sRGB) else { return }
                model.updateTheme {
                    $0.solidRed = Double(color.redComponent)
                    $0.solidGreen = Double(color.greenComponent)
                    $0.solidBlue = Double(color.blueComponent)
                }
            }
        )
    }
}
