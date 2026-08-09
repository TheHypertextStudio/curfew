import SwiftUI

/// Coordinator status-reporting panel for the Settings window.
///
/// The one place in Curfew that can start sending anything about this device to
/// a server. Written to be readable by someone who is suspicious of it: what
/// leaves, what does not, and where it goes — stated before the switch, not in
/// a disclosure triangle underneath it.
///
/// The endpoint field is empty on a fresh install and there is no default
/// behind it. Curfew ships with no coordinator address compiled in; the server
/// a user reports to is theirs to name.
extension SettingsView {
    /// The coordinator panel: the switch, the endpoint, the credential, the
    /// cadence, and the plain-language data statement.
    var coordinatorSyncPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Coordinator",
                subtitle: "Make this Mac's status visible from another machine"
            )

            Text(Self.coordinatorExplanation)
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            coordinatorConsentControl

            if model.settings.statusReporting.isEnabled {
                coordinatorEndpointControls
                coordinatorStatusLine
            }

            Divider()

            coordinatorDataStatement
        }
    }

    /// The switch. The "on" path goes through `enableDeviceStatusReporting()`
    /// rather than binding straight to the setting, because turning reporting
    /// on is also when this install mints its device identifier.
    private var coordinatorConsentControl: some View {
        Toggle(
            "Report status to a coordinator",
            isOn: Binding(
                get: { model.settings.statusReporting.isEnabled },
                set: { isOn in
                    if isOn {
                        model.enableDeviceStatusReporting()
                    } else {
                        model.disableDeviceStatusReporting()
                    }
                }
            )
        )
        .font(CurfewTypography.body(13))
    }

    private var coordinatorEndpointControls: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.small) {
            TextField(
                "https://curfew-sync.example.com",
                text: $model.settings.statusReporting.baseURL
            )
            .textFieldStyle(.roundedBorder)

            TextField(
                "Your account id on the coordinator",
                text: $model.settings.statusReporting.userID
            )
            .textFieldStyle(.roundedBorder)

            // The shared secret. Bound through the model rather than through
            // `settings`, because it is the one value on this panel that is not
            // written to the settings plist — it goes to the Keychain. See
            // `DeviceAssertionSecretStore` for why.
            SecureField(
                "Coordinator signing secret",
                text: Binding(
                    get: { model.deviceAssertionSecret },
                    set: { model.deviceAssertionSecret = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)

            Stepper(
                "Heartbeat every \(model.settings.statusReporting.heartbeatSeconds) s",
                value: $model.settings.statusReporting.heartbeatSeconds,
                in: DeviceStatusReportingPolicy.heartbeatFloorSeconds
                    ... DeviceStatusReportingPolicy.heartbeatCeilingSeconds,
                // Half the floor, so the range the coordinator's freshness
                // threshold leaves open (60–120 s) has a middle setting rather
                // than being a two-position switch.
                step: 30
            )
            .font(CurfewTypography.body(13))
        }
    }

    /// Says whether the current configuration would actually publish. A user
    /// who flipped the switch but typed something unusable should be told, not
    /// left to assume their other Mac can see this one.
    @ViewBuilder
    private var coordinatorStatusLine: some View {
        if model.isDeviceStatusReportingLive {
            Label(Self.coordinatorLiveNote, systemImage: "checkmark.circle")
                .font(CurfewTypography.label(12))
                .foregroundStyle(CurfewTheme.mutedInk)
        } else {
            Label(Self.coordinatorIdleNote, systemImage: "exclamationmark.triangle")
                .font(CurfewTypography.label(12))
                .foregroundStyle(CurfewTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var coordinatorDataStatement: some View {
        Text(Self.coordinatorDataNote)
            .font(CurfewTypography.body(12))
            .foregroundStyle(CurfewTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Why this exists, in one paragraph.
    static let coordinatorExplanation = """
    Curfew can tell a coordinator you run which phase this Mac is in, so another \
    machine can see it. Enforcement never depends on it: if the coordinator is \
    down, unreachable, or you are offline, this Mac still locks exactly when it \
    said it would.
    """

    /// Shown when the configuration resolves to a usable endpoint.
    static let coordinatorLiveNote = "Publishing on every phase change and on the heartbeat."

    /// Shown when it does not.
    static let coordinatorIdleNote = """
    Not publishing. The address needs to be a complete HTTPS URL — status \
    reports are not sent over plain HTTP — and the account id and signing \
    secret both need to be filled in, because every report is signed. The \
    secret is kept in your Keychain, not in Curfew's settings file.
    """

    /// What leaves the Mac, exhaustively.
    static let coordinatorDataNote = """
    What is sent: a device identifier Curfew generated for this purpose, the \
    enforcement phase (working, warning, locked, or day off), your time zone, a \
    one-way digest of your schedule, when the observation was taken, and when \
    the next change and the current lockout are due. That is the whole list. \
    Your schedule itself, your reflections, the apps you use, window titles, and \
    anything the camera sees stay on this Mac.
    """
}
