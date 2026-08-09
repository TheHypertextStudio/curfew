import Combine
import Foundation
import OSLog

/// Subsystem log for outbound status reporting. File-scoped so every line about
/// what left this Mac is filterable with one `category`.
private let deviceStatusLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "sync"
)

/// Per-model status-reporting runtime, keyed by model identity.
///
/// File-scoped for the same reason `CurfewAppModel+Presence.swift` and
/// `CurfewAppModel+Audit.swift` are: the model class sits at its lint-enforced
/// line budget. Every access is `@MainActor`, so the dictionary needs no lock.
private struct StatusReportingRuntime {
    /// The model this runtime was built for. Weak and checked on every lookup,
    /// because the dictionary key is an `ObjectIdentifier` — an address the
    /// allocator is free to reuse once a model deallocates. Without the check,
    /// a fresh model in a long test run would silently inherit its
    /// predecessor's reporter, and with it a `highestPublishedVersion` that
    /// would swallow its first reports.
    weak var owner: CurfewAppModel?

    /// The publisher. Created lazily, so a model that never reports (previews,
    /// fixtures, most of the suite) never constructs one.
    var reporter: DeviceStatusReporter

    /// Hands out the monotonic `statusVersion`. Bound to the settings store's
    /// own `UserDefaults` suite so a test's isolation covers it too.
    var versions: DeviceStatusVersionCounter

    /// When the last report went out. ``Date/distantPast`` until one has, so
    /// the heartbeat fires on the first eligible tick and needs no optional.
    var lastReportedAt: Date = .distantPast
}

private var statusReportingRuntimes: [ObjectIdentifier: StatusReportingRuntime] = [:]

/// Test seam: a transport to build the reporter around instead of the real
/// `URLSession`-backed one. Production leaves this empty. Carries the same weak
/// owner as ``StatusReportingRuntime``, for the same reason.
private struct StatusTransportOverride {
    weak var owner: CurfewAppModel?
    var transport: any DeviceStatusTransporting
}

private var statusTransportOverrides: [ObjectIdentifier: StatusTransportOverride] = [:]

/// Test seam: a secret store to sign with instead of the login keychain.
/// Production leaves this empty and resolves to
/// ``KeychainDeviceAssertionSecretStore/shared``, which is why no suite run can
/// write a credential onto the machine running it.
private struct StatusSecretStoreOverride {
    weak var owner: CurfewAppModel?
    var store: any DeviceAssertionSecretStoring
}

private var statusSecretStoreOverrides: [ObjectIdentifier: StatusSecretStoreOverride] = [:]

/// The live runtime for `model`, or `nil` when there is none belonging to it.
private func liveStatusRuntime(for model: CurfewAppModel) -> StatusReportingRuntime? {
    guard let runtime = statusReportingRuntimes[ObjectIdentifier(model)],
          runtime.owner === model else { return nil }
    return runtime
}

/// What prompted a status report. Log vocabulary only — it never reaches the
/// wire, because `DeviceStatusPublication` has no field for it and this file
/// does not coin one.
enum DeviceStatusTrigger: String {
    /// The enforcement engine moved between phases — a lockout started or
    /// ended, or a warning window opened. The transition D4 exists to make
    /// visible from another machine.
    case enforcementPhase = "enforcement_phase"

    /// The fused presence verdict moved. See ``publishDeviceStatus(trigger:)``
    /// for what this can and cannot convey.
    case presence

    /// Nothing changed; the cadence came round.
    case heartbeat

    /// The user turned reporting on, so the coordinator learns about this
    /// device without waiting for the first transition.
    case configuration
}

/// Outbound device-status reporting for `CurfewAppModel`.
///
/// **Nothing in this file may change enforcement.** Like the audit emitters, it
/// observes: if deleting a call from here altered when the Mac locks, the call
/// would be in the wrong place. The enforcement engine never reads a publish
/// outcome, and `tick()` never waits for one — see ``DeviceStatusReporter``,
/// where that property is structural rather than a convention.
@MainActor
extension CurfewAppModel {
    /// The reporter for this model, created and wired on first access.
    var deviceStatusReporter: DeviceStatusReporter {
        if let runtime = liveStatusRuntime(for: self) {
            return runtime.reporter
        }
        let identity = ObjectIdentifier(self)
        let override = statusTransportOverrides[identity]
        let transport: any DeviceStatusTransporting = override?.owner === self
            ? override?.transport ?? URLSessionDeviceStatusTransport()
            : URLSessionDeviceStatusTransport()
        let reporter = DeviceStatusReporter(transport: transport)
        statusReportingRuntimes[identity] = StatusReportingRuntime(
            owner: self,
            reporter: reporter,
            versions: DeviceStatusVersionCounter(defaults: settingsStore.storageDefaults)
        )
        return reporter
    }

    /// Test seam. Assigning a transport here builds this model's reporter
    /// around it, so a suite can drive reporting without a network.
    var deviceStatusTransportOverride: (any DeviceStatusTransporting)? {
        get {
            let override = statusTransportOverrides[ObjectIdentifier(self)]
            return override?.owner === self ? override?.transport : nil
        }
        set {
            let identity = ObjectIdentifier(self)
            guard let newValue else {
                statusTransportOverrides[identity] = nil
                return
            }
            statusTransportOverrides[identity] = StatusTransportOverride(
                owner: self,
                transport: newValue
            )
        }
    }

    // MARK: - Credential

    /// Where this model reads and writes the coordinator's shared signing
    /// secret. Production is the login keychain; tests install an in-memory
    /// store through ``deviceAssertionSecretStoreOverride``.
    var deviceAssertionSecretStore: any DeviceAssertionSecretStoring {
        let override = statusSecretStoreOverrides[ObjectIdentifier(self)]
        guard let override, override.owner === self else {
            return KeychainDeviceAssertionSecretStore.shared
        }
        return override.store
    }

    /// Test and preview seam. Assigning a store here makes this model sign with
    /// it instead of touching the keychain.
    var deviceAssertionSecretStoreOverride: (any DeviceAssertionSecretStoring)? {
        get {
            let override = statusSecretStoreOverrides[ObjectIdentifier(self)]
            return override?.owner === self ? override?.store : nil
        }
        set {
            let identity = ObjectIdentifier(self)
            guard let newValue else {
                statusSecretStoreOverrides[identity] = nil
                return
            }
            statusSecretStoreOverrides[identity] = StatusSecretStoreOverride(
                owner: self,
                store: newValue
            )
        }
    }

    /// The shared secret, as the Settings panel reads and writes it. Empty when
    /// the user has not configured one, which is the state a fresh install is
    /// in and the state in which nothing is published.
    ///
    /// Writing publishes `objectWillChange` by hand: the value lives in the
    /// keychain rather than in `settings`, so nothing else would tell the
    /// Settings panel that ``isDeviceStatusReportingLive`` has just changed.
    var deviceAssertionSecret: String {
        get { deviceAssertionSecretStore.secret }
        set {
            objectWillChange.send()
            deviceAssertionSecretStore.store(newValue)
        }
    }

    /// The assertion this device would sign at `now`, ready for the
    /// `Authorization` header — or `nil` when it cannot sign one.
    ///
    /// Every claim comes from configuration the user entered or Curfew minted:
    /// the account, this install's device identifier, and the clock. There is
    /// no path here that invents one.
    func deviceStatusCredential(at now: Date) -> String? {
        let policy = settings.statusReporting
        let assertion = DeviceIdentityAssertion(
            userID: policy.userID,
            deviceID: policy.deviceID,
            issuedAt: now
        )
        return assertion.compactJWS(signedWith: deviceAssertionSecretStore.secret)
    }

    // MARK: - Publishing

    /// Publishes this device's current status, if the user has configured a
    /// coordinator. Returns immediately in every case, including the ones where
    /// it publishes nothing.
    ///
    /// `trigger` records why, for the log. It is not on the wire:
    /// `DeviceStatusPublication` has no field for it, and inventing one would
    /// break the rule that wire-crossing shapes come from curfew-protocols.
    ///
    /// The presence trigger deserves a note, because what it does is narrower
    /// than it looks. `DeviceStatusPublication` carries no presence field —
    /// there is nowhere in the schema to say "a person is at this machine" — so
    /// a presence transition cannot publish presence. What it publishes is a
    /// fresh `observedAt` alongside the enforcement scalars: the coordinator
    /// learns this device is alive and what phase it is in as of a moment that
    /// just mattered. Carrying the verdict itself needs a curfew-protocols
    /// change, not a field added here.
    func publishDeviceStatus(trigger: DeviceStatusTrigger) {
        let policy = settings.statusReporting
        guard let endpoint = policy.resolvedEndpoint else { return }
        // The same "off unless configured" contract the endpoint has, extended
        // to the credential: an unset shared secret, an unset account, or an
        // unset device identifier means this device signs nothing and therefore
        // sends nothing. Checked before the version counter is advanced, so a
        // half-configured install does not silently consume `statusVersion`s.
        guard let credential = deviceStatusCredential(at: currentTime) else { return }
        guard let runtime = liveStatusRuntimeEnsuringExists() else { return }
        let report = DeviceStatusReport(
            deviceID: policy.deviceID,
            phase: state.phase,
            timeZone: TimeZone.current.identifier,
            scheduleDigest: DeviceStatusReport.scheduleDigest(for: settings.schedule),
            statusVersion: runtime.versions.next(),
            observedAt: currentTime,
            nextTransitionAt: nextEnforcementTransition,
            activeLockoutEndsAt: state.phase == .locked ? state.unlockDate : nil
        )
        statusReportingRuntimes[ObjectIdentifier(self)]?.lastReportedAt = currentTime
        deviceStatusLogger.debug("Reporting device status (\(trigger.rawValue, privacy: .public))")
        runtime.reporter.report(report, endpoint: endpoint, bearerToken: credential)
    }

    /// Publishes a heartbeat when the configured cadence has elapsed. Called
    /// once per tick; a no-op on every tick that isn't due, and on every tick
    /// at all when reporting is off.
    ///
    /// Event-driven reports are what make status *timely*; this is what makes a
    /// device that has been sitting in one phase all afternoon distinguishable
    /// from one that crashed at lunchtime.
    func publishDeviceStatusHeartbeatIfDue() {
        // Deliberately the cheap half of the gate. This runs once a second;
        // `publishDeviceStatus` makes the credential check, which touches the
        // keychain, and it only runs when the cadence has actually come round.
        guard settings.statusReporting.resolvedEndpoint != nil else { return }
        guard let runtime = liveStatusRuntimeEnsuringExists() else { return }
        let elapsed = currentTime.timeIntervalSince(runtime.lastReportedAt)
        guard elapsed >= Double(settings.statusReporting.heartbeatSeconds) else { return }
        publishDeviceStatus(trigger: .heartbeat)
    }

    /// When the current phase is next expected to change, as far as this tick
    /// can tell: the lock moment while the day is still open, the unlock moment
    /// while locked, and nothing at all on a day off.
    private var nextEnforcementTransition: Date? {
        switch state.phase {
        case .working, .warning: state.lockDate
        case .locked: state.unlockDate
        case .dayOff: nil
        }
    }

    /// Reads the runtime, constructing it first if this model has none.
    /// Central because both publish paths need the same "touch the lazy
    /// property, then read the dictionary" dance.
    private func liveStatusRuntimeEnsuringExists() -> StatusReportingRuntime? {
        _ = deviceStatusReporter
        return liveStatusRuntime(for: self)
    }

    // MARK: - Configuration

    /// Turns status reporting on, minting this install's device identifier if
    /// it does not have one yet, and publishes once so the coordinator learns
    /// about the device immediately.
    ///
    /// The identifier is a fresh random UUID, lowercased to satisfy the
    /// schema's `CanonicalUUID` pattern. Deliberately not the machine's
    /// hardware UUID: a value only Curfew knows cannot be joined against
    /// anything else that identifies this Mac.
    func enableDeviceStatusReporting() {
        if settings.statusReporting.deviceID.isEmpty {
            settings.statusReporting.deviceID = UUID().uuidString.lowercased()
        }
        settings.statusReporting.isEnabled = true
        publishDeviceStatus(trigger: .configuration)
    }

    /// Turns status reporting off. The device identifier is kept, so switching
    /// back on later resumes the same device rather than appearing to the
    /// coordinator as a second Mac.
    func disableDeviceStatusReporting() {
        settings.statusReporting.isEnabled = false
    }

    /// Whether the current configuration would actually publish. Drives the
    /// Settings panel's status line, so a user who has switched reporting on
    /// but typed an unusable URL — or has not pasted the coordinator's shared
    /// secret — is told so rather than left assuming.
    ///
    /// Both halves are required because both are required at the coordinator: a
    /// report with no address goes nowhere, and a report with no assertion is
    /// answered 401.
    var isDeviceStatusReportingLive: Bool {
        guard settings.statusReporting.resolvedEndpoint != nil else { return false }
        let policy = settings.statusReporting
        let assertion = DeviceIdentityAssertion(
            userID: policy.userID,
            deviceID: policy.deviceID,
            issuedAt: currentTime
        )
        return assertion.isWellFormed && !deviceAssertionSecretStore.secret.isEmpty
    }
}
