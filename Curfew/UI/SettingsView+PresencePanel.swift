import SwiftUI

/// Presence-detection panel for the Settings window.
///
/// This is where camera consent is given and withdrawn, and it is the only
/// place in Curfew that can turn the camera on. The panel is written to be
/// readable by someone who is suspicious of it: it states what is captured,
/// what is derived, and what is kept, in that order, before offering the
/// switch — not in a disclosure triangle underneath it.
extension SettingsView {
    /// The presence panel: live camera indicator, the consent switch, the
    /// nudge controls, and the plain-language data statement.
    var presencePanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Presence",
                subtitle: "Telling an empty chair from a quiet one"
            )

            Text(Self.presenceExplanation)
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            // Above the switch, not below it: if the camera is live the user
            // should see that before they see anything else in this panel.
            CameraLiveIndicator(isLive: model.isPresenceCameraLive) {
                model.disablePresenceDetection()
            }

            Divider()

            presenceConsentControl

            if model.settings.presence.cameraEnabled {
                presenceStatusLine
                Divider()
                presenceNudgeControls
            }

            Divider()

            presenceDataStatement
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
            Toggle(
                "Use the camera to detect whether I'm at my Mac",
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
        Toggle(
            "Nudge me when I'm here but not working",
            isOn: $model.settings.presence.warnsWhenDistracted
        )

        Stepper(
            "Nudge after: \(model.settings.presence.distractionSustainedSeconds / 60) min still",
            value: presenceMinutesBinding(\.distractionSustainedSeconds),
            in: DistractionWarningPolicy.sustainedFloorSeconds / 60
                ... DistractionWarningPolicy.sustainedCeilingSeconds / 60
        )
        .disabled(!model.settings.presence.warnsWhenDistracted)

        Stepper(
            "Then at most every: \(model.settings.presence.distractionRepeatSeconds / 60) min",
            value: presenceMinutesBinding(\.distractionRepeatSeconds),
            in: DistractionWarningPolicy.repeatFloorSeconds / 60
                ... DistractionWarningPolicy.repeatCeilingSeconds / 60,
            step: 5
        )
        .disabled(!model.settings.presence.warnsWhenDistracted)

        Text(Self.presenceNudgeNote)
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The captured / derived / retained statement, always visible whether or
    /// not the feature is on. Someone deciding whether to turn it on needs it
    /// more than someone who already has.
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
    Curfew already knows when your keyboard and trackpad go quiet, but not \
    why. Reading a long document and leaving for the afternoon look identical \
    to it. Turning this on lets Curfew check the camera for a person, so it \
    can tell the two apart — and stop counting an empty room as work.
    """

    /// Shown when Screen Time or an MDM profile bars camera access.
    static let presenceRestrictedNote = """
    Camera access is blocked by a profile on this Mac, so presence detection \
    can't run. Nothing Curfew can change.
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
    Nudges are quiet banners, never a lockout, and they're only sent while \
    you're at the Mac. Walking away doesn't trigger one, and neither does \
    anything during a curfew.
    """

    /// The captured / derived / retained facts, as bullets.
    ///
    /// Ordered from what is most alarming to read to what is most reassuring,
    /// because a list that opens with the reassurance reads as a sales pitch.
    static let presenceDataFacts = [
        "Captured: video frames from the camera, about one every two seconds, "
            + "held in memory only for as long as it takes to look at them.",
        "Derived: one yes-or-no answer — was a person visible — and the time "
            + "it was taken. No identity, no face print, no photo, no count.",
        "Retained: the yes-or-no answer, until the next one replaces it. "
            + "Frames are never written to disk and never leave this Mac.",
        "Recorded: changes between working, present but idle, and away go to "
            + "Curfew's audit log, along with every time the camera starts and "
            + "stops. Images never do.",
        "Off means off: switching this off ends the capture session and "
            + "releases the camera. Curfew ships with it off."
    ]

    /// One-line rendering of a ``PresenceState`` for the status line.
    static func presenceDescription(_ state: PresenceState) -> String {
        switch state {
        case .working:
            "working — you're using this Mac"
        case .presentButIdle:
            "here, but not typing"
        case .absent:
            "away — the camera doesn't see anyone"
        case .unknown:
            "quiet, and Curfew can't tell why"
        }
    }
}
