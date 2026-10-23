import CurfewKit
import SwiftUI

/// Camera consent facts remain above the switch so users can read them before enabling capture.
extension SettingsView {
    /// The presence panel: live camera indicator, the consent switch, the
    /// nudge controls, and the plain-language data statement.
    var presencePanel: some View {
        Group {
            Section {
                Text(Self.presenceExplanation)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                CameraLiveIndicator(isLive: model.isPresenceCameraLive) {
                    model.disablePresenceDetection()
                }
                Text(Self.presencePrivacySummary)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                presenceConsentControl
                if model.settings.presence.cameraEnabled {
                    presenceStatusLine
                }
                DisclosureGroup("Camera data and privacy", isExpanded: $showsPresencePrivacy) {
                    presenceDataStatement
                        .padding(.top, 8)
                }
            }
            if model.settings.presence.cameraEnabled {
                Section {
                    CurfewSectionTitle(title: "Reminders")
                    presenceNudgeControls
                }
            }
        }
    }

    /// The consent switch, or a route to System Settings when macOS is the one
    /// saying no.
    ///
    /// A plain `Toggle` bound straight to the setting would let the user switch
    /// presence detection on while camera access is denied — a stored intent to
    /// run a camera that cannot run. Instead the "on" path goes through
    /// `enablePresenceDetection()`, which prompts first and only persists the
    /// setting if access was actually granted.
    @ViewBuilder
    private var presenceConsentControl: some View {
        switch model.presenceCameraAuthorization {
        case .restricted:
            Label(Self.presenceRestrictedNote, systemImage: "lock.fill")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.presenceDeniedNote)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Camera Settings") {
                    model.openCameraPrivacySettings()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
            }
        case .notDetermined, .authorized:
            SettingsToggleRow(
                title: "Use the camera to detect whether I'm at my Mac",
                isOn: Binding(
                    get: { model.settings.presence.cameraEnabled },
                    set: { wantsOn in
                        if wantsOn {
                            model.enablePresenceDetection()
                        } else {
                            model.disablePresenceDetection()
                        }
                    }
                )
            )
        }
    }

    /// What Curfew currently believes, stated plainly. Doubles as the failure
    /// surface: a camera that will not open says so here instead of leaving
    /// the panel looking like everything works.
    @ViewBuilder
    private var presenceStatusLine: some View {
        if model.isPresenceCameraStalled {
            Label(Self.presenceStalledNote, systemImage: "video.slash")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Right now: \(Self.presenceDescription(model.presenceState))")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The nudge switch and its two windows. Shown only once the camera is on,
    /// because without it the nudge can never fire and a live-looking control
    /// that does nothing is worse than no control.
    @ViewBuilder
    private var presenceNudgeControls: some View {
        @Bindable var model = model
        SettingsToggleRow(
            title: "Remind me when I'm at my Mac but inactive.",
            isOn: $model.settings.presence.warnsWhenDistracted
        )

        SettingsValueRow(
            title: "Additional delay", value: presenceMinutesBinding(\.distractionSustainedSeconds),
            range: DistractionWarningPolicy.sustainedFloorSeconds / 60
                ... DistractionWarningPolicy.sustainedCeilingSeconds / 60,
            usesMinutes: true
        )
        .disabled(!model.settings.presence.warnsWhenDistracted)

        SettingsValueRow(
            title: "Repeat at most every",
            value: presenceMinutesBinding(\.distractionRepeatSeconds),
            range: DistractionWarningPolicy.repeatFloorSeconds / 60
                ... DistractionWarningPolicy.repeatCeilingSeconds / 60,
            step: 5, usesMinutes: true
        )
        .disabled(!model.settings.presence.warnsWhenDistracted)

        Text(Self.presenceNudgeNote)
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Detailed consent facts accompany the always-visible frame-use summary.
    private var presenceDataStatement: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What the camera does and doesn't do")
                .font(CurfewTypography.bodyEmphasis(12))
            ForEach(Self.presenceDataFacts, id: \.self) { fact in
                Text("• \(fact)")
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Bridges a seconds-valued setting to a minutes-valued stepper.
    private func presenceMinutesBinding(
        _ keyPath: WritableKeyPath<PresenceDetectionPolicy, Int>
    ) -> Binding<Int> {
        Binding(
            get: { model.settings.presence[keyPath: keyPath] / 60 },
            set: { model.settings.presence[keyPath: keyPath] = $0 * 60 }
        )
    }

    // MARK: - Copy

    /// Lead paragraph. Names the limitation of the existing signal first, so
    /// the camera reads as an answer to a stated problem rather than a
    /// capability looking for a justification.
    static let presenceExplanation = """
    Curfew uses the camera to estimate whether someone is at your Mac. \
    It cannot tell whether you're working.
    """

    static let presencePrivacySummary = """
    Camera frames stay on this Mac. Curfew does not save images or identify people.
    """

    /// Shown when Screen Time or an MDM profile bars camera access.
    static let presenceRestrictedNote = """
    Camera access is blocked by a profile on this Mac, so presence detection \
    can't run. Contact the person who manages this Mac to change the restriction.
    """

    /// Shown when the user has refused or revoked camera access.
    static let presenceDeniedNote = """
    Curfew doesn't have camera access. Presence detection stays off until you \
    grant it in System Settings → Privacy & Security → Camera.
    """

    /// Shown when the setting is on and access is granted, but no session.
    static let presenceStalledNote = """
    Presence detection is on, but the camera isn't available — another app may \
    be using it. Curfew is falling back to keyboard activity alone.
    """

    /// Explains what the nudge will and won't interrupt.
    static let presenceNudgeNote = """
    Curfew detects inactivity after \(Int(IdleWatcher.defaultIdleThresholdSeconds) / 60) \
    minutes without keyboard or pointer input. The additional delay starts when \
    the camera detects a person and Curfew detects inactivity. Reminders do not \
    start a lockout. Curfew does not show them during lockout or when the camera \
    detects no person.
    """

    /// The captured / derived / retained facts, as bullets.
    ///
    /// Ordered from what is most alarming to read to what is most reassuring,
    /// because a list that opens with the reassurance reads as a sales pitch.
    static let presenceDataFacts = [
        "Captured: video frames from the camera, about one every two seconds, "
            + "kept in memory only while Curfew analyses them.",
        "Derived: one yes-or-no answer — was a person visible — and the time "
            + "it was taken. No identity, no face print, no photo, no count.",
        "Retained: the yes-or-no answer, until the next one replaces it. "
            + "Frames are never written to disk and never leave this Mac.",
        "Recorded: changes in input activity and estimated presence go to "
            + "Curfew's audit log, along with every time the camera starts and "
            + "stops. The log contains no images.",
        "Switching this off ends the capture session and "
            + "releases the camera. Curfew ships with it off."
    ]

    /// One-line rendering of a ``PresenceState`` for the status line.
    static func presenceDescription(_ state: PresenceState) -> String {
        switch state {
        case .working:
            "recent keyboard or pointer input"
        case .presentButIdle:
            "person detected, but no recent input"
        case .absent:
            "no person detected by the camera"
        case .unknown:
            "Curfew can't determine whether you're at your Mac."
        }
    }
}
