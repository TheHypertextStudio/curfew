@testable import Curfew
import Foundation

/// Test-only helpers for exercising the audit log without touching
/// `~/Library/Logs/Curfew`.
///
/// Mirrors ``ActivityTestSupport``: every test gets its own temp directory so
/// the suite stays hermetic and parallel-safe, and the directory is left on
/// disk for the same reason (macOS reaps `/var/folders` on its own, and
/// cleanup code in every test would only make failures noisier).
enum AuditTestSupport {
    /// A fresh temp directory keyed off `label`.
    static func makeDirectory(label: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "curfew-audit-\(label)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    /// A writer rooted in a fresh temp directory.
    static func makeWriter(
        label: String,
        stream: AuditStream = .app,
        policy: AuditRotationPolicy = .standard
    ) throws -> AuditLogWriter {
        try AuditLogWriter(
            stream: stream,
            directory: makeDirectory(label: label),
            baseName: "curfew-\(label)",
            policy: policy,
            filePermissions: 0o600
        )
    }

    /// Non-empty lines of `url`, or an empty array when the file is absent.
    static func lines(of url: URL) -> [String] {
        guard
            let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8)
        else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// Parses one written line into a dictionary. Fails the caller's
    /// expectation by returning `nil` rather than throwing, so tests read as
    /// assertions rather than error plumbing.
    static func parse(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Every record in `url`, parsed, in write order.
    static func records(in url: URL) -> [[String: Any]] {
        lines(of: url).compactMap(parse)
    }
}

/// Hermetic defaults for model tests that do not care about durable storage.
/// A synthetic test lockout must never write into the developer's live Curfew
/// support directory, especially when the login session is locked.
enum ModelTestSupport {
    static func lockoutDeadlineStore() -> LockoutDeadlineStore {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-model-deadline-\(UUID().uuidString).json")
        return LockoutDeadlineStore(recordURL: recordURL)
    }

    @MainActor
    static func makeModel() -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: lockoutDeadlineStore(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
    }
}

/// In-memory ``AuditLogWriting`` that keeps records instead of writing them.
///
/// Used by the wiring tests, which care that the right event was emitted with
/// the right actor and detail, not about the byte format — that is
/// `AuditLineEncoderTests`' job.
final class RecordingAuditWriter: AuditLogWriting {
    private(set) var records: [AuditRecord] = []

    func append(_ record: AuditRecord) {
        records.append(record)
    }

    /// Every record of the given type, in write order.
    func records(ofType type: AuditEventType) -> [AuditRecord] {
        records.filter { $0.event == type }
    }

    /// The first record of the given type, or `nil`.
    func first(_ type: AuditEventType) -> AuditRecord? {
        records.first { $0.event == type }
    }
}
