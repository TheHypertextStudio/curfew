import AppKit
import CoreGraphics
import CurfewAtmosphere
import CurfewKit
import SwiftUI
import UniformTypeIdentifiers

/// Local appearance controls embedded in the existing Settings form.
struct RestScreenSettingsView: View {
    @Environment(CurfewAppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var draft = RestAppearanceDraft(RestAppearancePreferences())
    @State private var backgroundImage: CGImage?
    @State private var choosingImage = false
    @State private var imageError: String?
    @State private var imageOperationInProgress = false
    @State private var imageTask: Task<Void, Never>?

    var body: some View {
        Group {
            Section {
                TimelineView(.animation(minimumInterval: reduceMotion || draft
                        .staticBackground ? 1 : 1.0 / 30)) { context in
                    RestAmbientScene(
                        snapshot: RestSceneSnapshot(
                            version: 1, expiresAt: .distantFuture, appearance: draft.preferences,
                            lockDate: nil, unlockDate: nil
                        ),
                        date: context.date,
                        image: backgroundImage,
                        reduceMotion: reduceMotion,
                        reduceTransparency: reduceTransparency,
                        clockSize: 52
                    )
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Rest screen preview")
                .accessibilityIdentifier("rest-appearance-preview")
            }
            Section("Background") {
                Picker("Background", selection: $draft.background) {
                    Text("Atmosphere").tag(RestAppearancePreferences.Background.atmosphere)
                    Text("Solid color").tag(RestAppearancePreferences.Background.solid)
                    Text("Image").tag(RestAppearancePreferences.Background.image)
                }
                .accessibilityIdentifier("rest-background-choice")
                .disabled(imageOperationInProgress)
                Picker("Palette", selection: $draft.palette) {
                    Text("Sundown").tag(RestAppearancePreferences.Palette.sundown)
                    Text("Warm amber").tag(RestAppearancePreferences.Palette.warmAmber)
                    Text("Cool twilight").tag(RestAppearancePreferences.Palette.coolTwilight)
                }
                .accessibilityIdentifier("rest-palette-choice")
                if draft.background == .solid {
                    ColorPicker("Background color", selection: solidColor, supportsOpacity: false)
                }
                if draft.background == .image {
                    Button("Choose image…") { choosingImage = true }
                        .disabled(imageOperationInProgress)
                    if draft.ownedImageFilename != nil {
                        Button("Remove image", role: .destructive) {
                            imageTask = Task { await removeImage() }
                        }
                        .disabled(imageOperationInProgress)
                        Slider(value: $draft.focalX, in: 0 ... 1) { Text("Horizontal focus") }
                        Slider(value: $draft.focalY, in: 0 ... 1) { Text("Vertical focus") }
                    }
                }
                if let imageError {
                    Text(imageError).foregroundStyle(CurfewTheme.mutedInk)
                }
                Toggle("Static background", isOn: $draft.staticBackground)
                    .toggleStyle(.switch)
                Text("Reduce Motion also keeps the atmosphere still.")
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
            Section("Clock and message") {
                Picker("Clock style", selection: $draft.clockStyle) {
                    Text("Rounded").tag(RestAppearancePreferences.ClockStyle.rounded)
                    Text("Standard").tag(RestAppearancePreferences.ClockStyle.standard)
                    Text("Serif").tag(RestAppearancePreferences.ClockStyle.serif)
                }
                .accessibilityIdentifier("rest-clock-style")
                Picker("Ambient clock position", selection: $draft.clockPosition) {
                    Text("Center").tag(RestAppearancePreferences.ClockPosition.center)
                    Text("Upper center").tag(RestAppearancePreferences.ClockPosition.upperCenter)
                    Text("Lower left").tag(RestAppearancePreferences.ClockPosition.lowerLeft)
                }
                .accessibilityIdentifier("rest-clock-position")
                TextField("Personal message", text: $draft.message)
                    .accessibilityIdentifier("rest-personal-message")
                    .onChange(of: draft.message) { _, message in
                        if message.count > 140 {
                            draft.message = String(message.prefix(140))
                        }
                    }
                Text("\(draft.message.count)/140 characters")
                    .font(.caption).foregroundStyle(CurfewTheme.mutedInk)
                Toggle("Show personal message in screensaver", isOn: $draft.saverMessageEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("rest-saver-message")
            }
            RestScreenSaverSetupSection()
            Section("Sunrise") {
                Toggle("Automatically wake for Sunrise", isOn: $draft.sunriseWakeEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("rest-sunrise-wake")
                Stepper(
                    "Begin \(draft.sunriseLeadMinutes) minutes before unlock",
                    value: $draft.sunriseLeadMinutes,
                    in: 5 ... 60
                )
                Toggle("Allow Sunrise on battery", isOn: $draft.sunriseOnBatteryEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("rest-sunrise-battery")
                Text(sunriseStatusText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(sunriseStatusText)
                    .accessibilityIdentifier("rest-sunrise-status")
                Text(
                    """
                    Sunrise follows your scheduled unlock. External power is required \
                    unless you allow battery use. Your Mac’s usual authentication still applies.
                    """
                )
                .foregroundStyle(CurfewTheme.mutedInk)
            }
        }
        .pickerStyle(.menu)
        .task(id: draft.ownedImageFilename) {
            let directory = model.restBackgroundDirectory
            let filename = draft.ownedImageFilename
            let image = await Task.detached(priority: .userInitiated) {
                RestBackgroundImageStore(directory: directory).image(named: filename)
            }.value
            guard !Task.isCancelled else { return }
            backgroundImage = image
        }
        .onAppear { draft = RestAppearanceDraft(model.restAppearance) }
        .onDisappear {
            imageTask?.cancel()
            imageTask = nil
        }
        .onChange(of: draft) { _, value in
            var saved = value
            if saved.background == .image, saved.ownedImageFilename == nil {
                saved.background = model.restAppearance.background
            }
            model.restAppearance = saved.preferences
        }
        .onChange(of: choosingImage) { _, presented in
            if !presented, draft.background == .image, draft.ownedImageFilename == nil {
                draft.background = model.restAppearance.background
            }
        }
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [
            .jpeg,
            .png,
            .heic
        ]) { result in
            imageTask = Task { await importImage(result) }
        }
    }

    private var solidColor: Binding<Color> {
        Binding(
            get: {
                AtmospherePalette.solidBackground(
                    red: draft.solidRed, green: draft.solidGreen, blue: draft.solidBlue
                )
            },
            set: { color in
                guard let color = NSColor(color).usingColorSpace(.sRGB) else { return }
                draft.solidRed = Double(color.redComponent)
                draft.solidGreen = Double(color.greenComponent)
                draft.solidBlue = Double(color.blueComponent)
            }
        )
    }

    @MainActor
    private func importImage(_ result: Result<URL, Error>) async {
        imageOperationInProgress = true
        defer { imageOperationInProgress = false }
        do {
            let source = try result.get()
            let directory = model.restBackgroundDirectory
            let imported = try await Task.detached(priority: .userInitiated) {
                let granted = source.startAccessingSecurityScopedResource()
                defer {
                    if granted {
                        source.stopAccessingSecurityScopedResource()
                    }
                }
                return try RestBackgroundImageStore(directory: directory).importImage(from: source)
            }.value
            guard !Task.isCancelled else {
                try? await Task.detached(priority: .utility) {
                    try RestBackgroundImageStore(directory: directory).removeImage(at: imported)
                }.value
                return
            }
            let previousFilename = model.restAppearance.ownedImageFilename
            var current = RestAppearanceDraft(model.restAppearance)
            current.ownedImageFilename = imported.lastPathComponent
            current.background = .image
            draft = current
            imageError = nil
            // Merge into current preferences before retiring the previous owned asset.
            model.restAppearance = current.preferences
            if let previousFilename, previousFilename != imported.lastPathComponent {
                do {
                    try await Task.detached(priority: .utility) {
                        try RestBackgroundImageStore(directory: directory).removeImage(
                            at: directory.appendingPathComponent(previousFilename)
                        )
                    }.value
                } catch {
                    imageError = "Your new image is saved. The previous copy could not be removed."
                }
            }
        } catch {
            draft.background = model.restAppearance.background
            if (error as NSError).code != NSUserCancelledError {
                imageError = "The image could not be imported. Your background has been kept."
            }
        }
    }

    @MainActor
    private func removeImage() async {
        guard let filename = draft.ownedImageFilename else { return }
        imageOperationInProgress = true
        defer { imageOperationInProgress = false }
        let directory = model.restBackgroundDirectory
        do {
            try await Task.detached(priority: .userInitiated) {
                try RestBackgroundImageStore(directory: directory)
                    .removeImage(at: directory.appendingPathComponent(filename))
            }.value
            // A newer settings view may have changed unrelated choices meanwhile.
            if model.restAppearance.ownedImageFilename == filename {
                var current = RestAppearanceDraft(model.restAppearance)
                current.ownedImageFilename = nil
                if current.background == .image {
                    current.background = .atmosphere
                }
                model.restAppearance = current.preferences
                draft = current
            }
            imageError = nil
        } catch {
            imageError = "The image could not be removed. Your background has been kept."
        }
    }
}

private extension RestScreenSettingsView {
    var sunriseStatusText: String {
        guard draft.sunriseWakeEnabled else { return "Sunrise is off." }
        switch model.sunriseStatus {
        case .disabled:
            return "Sunrise is waiting to connect."
        case .waitingForSchedule:
            return "Waiting for a scheduled unlock."
        case .scheduled:
            return "Wake scheduled for Sunrise."
        case .dismissed:
            return "Sunrise was dismissed for this morning."
        case .displayRequested:
            return "Sunrise display wake requested."
        case .helperUnavailable:
            return "Sunrise needs the Curfew helper. Install or repair it in Protection settings."
        case .requestRejected:
            return "The Sunrise wake request was rejected. Check Protection settings."
        case .batteryExcluded:
            return "Sunrise is paused on battery. Connect power or allow battery use."
        }
    }
}
