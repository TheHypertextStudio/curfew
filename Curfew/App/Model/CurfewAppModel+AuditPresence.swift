import Foundation

/// Audit-log emitters for presence detection.
///
/// Split from `CurfewAppModel+Audit.swift` to stay inside the file-length
/// budget, and separated conceptually because this is the one subsystem where
/// what is *not* written matters as much as what is.
///
/// **Nothing here can carry an image.** `AuditValue` admits only strings,
/// integers, doubles, and booleans, so there is no representation for a frame,
/// a crop, a bounding box, or a thumbnail even if a future edit wanted one.
/// What these records hold is the derived verdict — `detected`,
/// `not_detected`, `unavailable` — plus the configuration that produced it.
/// Not a person count, not a position, not a confidence: those exist for
/// microseconds inside `VisionCameraPresenceSensor` and are discarded on the
/// line that computes the boolean.
///
/// The camera lifecycle pair is deliberately redundant with the state records.
/// `presence.camera_started` / `presence.camera_stopped` bound every window
/// the camera light was on, and an auditor asking "when could this app have
/// been watching me?" should be able to answer it by grepping two event names
/// rather than by reasoning about settings history.
@MainActor
extension CurfewAppModel {
    /// Records the fused presence verdict when it moves.
    ///
    /// Folded into the tick's single audit call alongside the HID-only
    /// `presence.changed`, which is kept unchanged so parsers written against
    /// the older format keep working. The two disagree by design: `active` /
    /// `idle` is one signal, `working` / `present_idle` / `absent` / `unknown`
    /// is both.
    ///
    /// `actor` is `system` — macOS's HID idle clock and the camera are what
    /// produced this, not a decision Curfew made.
    func recordAuditPresenceState() {
        let presence = settings.presence
        auditLog.emitIfChanged(
            key: "presenceState",
            to: AuditTokens.presenceState(presenceState),
            event: .presenceStateChanged,
            actor: .system,
            detail: [
                "personSignal": .string(AuditTokens.personSignal(presenceSignal)),
                "hidIdle": .bool(isUserIdle),
                "idleThresholdSeconds": .int(Int(idleWatcher.idleThresholdSeconds)),
                "cameraEnabled": .bool(presence.cameraEnabled),
                "cameraLive": .bool(isPresenceCameraLive),
                "cameraAuthorization": .string(
                    AuditTokens.cameraAuthorization(presenceCameraAuthorization)
                ),
                "phase": .string(AuditTokens.phase(state.phase))
            ],
            at: currentTime
        )
    }

    /// Records the camera coming on. Emitted from the monitor's callback, so
    /// it lands before the first frame can be analysed — the record always
    /// precedes any use of the device it describes.
    func recordAuditCameraStarted() {
        auditLog.emit(
            .presenceCameraStarted,
            actor: .app,
            detail: [
                "authorization": .string(
                    AuditTokens.cameraAuthorization(presenceCameraAuthorization)
                ),
                "analysisIntervalSeconds": .double(
                    PresenceDetectionPolicy.analysisIntervalSeconds
                ),
                "phase": .string(AuditTokens.phase(state.phase))
            ],
            at: currentTime
        )
    }

    /// Records the camera going off, and why.
    func recordAuditCameraStopped(_ reason: CameraStopReason) {
        auditLog.emit(
            .presenceCameraStopped,
            actor: .app,
            detail: [
                "reason": .string(reason.rawValue),
                "phase": .string(AuditTokens.phase(state.phase))
            ],
            at: currentTime
        )
    }

    /// Records camera consent being granted, refused, or withdrawn.
    ///
    /// `actor` is `system`: TCC owns this transition. A grant the user makes
    /// inside Curfew's own prompt still arrives here through the same system
    /// callback, and attributing it to `user` would claim more about where the
    /// click happened than Curfew can actually observe.
    func recordAuditCameraAuthorization(
        from previous: CameraAuthorization,
        to current: CameraAuthorization
    ) {
        auditLog.emit(
            .presenceCameraAuthorizationChanged,
            actor: .system,
            from: AuditTokens.cameraAuthorization(previous),
            to: AuditTokens.cameraAuthorization(current),
            detail: ["cameraEnabled": .bool(settings.presence.cameraEnabled)],
            at: currentTime
        )
    }

    /// Records a delivered distraction nudge.
    ///
    /// The notification's copy is app-authored and fixed, so there is nothing
    /// user-written to redact — but the record still carries only the shape of
    /// the event (how long, against what threshold) rather than the text.
    func recordAuditDistractionWarning(sustainedSeconds: TimeInterval) {
        let policy = settings.presence.distractionPolicy
        auditLog.emit(
            .presenceDistractionWarned,
            actor: .app,
            detail: [
                "state": .string(AuditTokens.presenceState(presenceState)),
                "sustainedSeconds": .int(Int(sustainedSeconds)),
                "thresholdSeconds": .int(Int(policy.sustainedSeconds)),
                "repeatSeconds": .int(Int(policy.repeatSeconds)),
                "phase": .string(AuditTokens.phase(state.phase))
            ],
            at: currentTime
        )
    }
}
