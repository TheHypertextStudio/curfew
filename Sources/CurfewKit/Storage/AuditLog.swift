import Foundation
import OSLog

private let auditLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "audit-log"
)

/// Process-wide entry point for writing audit records.
///
/// Every emitter in the app, the daemon, and the CLI goes through one of
/// these. A process installs exactly one at startup — ``bootstrap(stream:)``
/// for production, ``install(_:)`` for tests — and everything else reaches it
/// through ``shared``.
///
/// Until a process installs one, ``shared`` is a disabled instance that
/// silently drops records. That default matters: it keeps the unit-test host
/// and the SwiftUI preview harness from writing into the real
/// `~/Library/Logs/Curfew`, and it means a call site never has to check
/// whether logging is configured.
public final class AuditLog: @unchecked Sendable {
    private let writer: AuditLogWriting?
    private let stream: AuditStream
    private let lock = NSLock()

    /// Last value seen for each `emitIfChanged` key, so callers polled at
    /// 1 Hz can hand over the current state every tick and get a record only
    /// on an actual transition. Holding the memo here rather than in
    /// `CurfewAppModel` keeps the tick-loop call site to a single line and
    /// keeps transition detection out of the app's stored state.
    private var lastObserved: [String: String] = [:]

    /// Wraps `writer`. Pass `nil` for a log that discards everything.
    public init(stream: AuditStream, writer: AuditLogWriting?) {
        self.stream = stream
        self.writer = writer
    }

    /// A log that drops every record.
    public static func disabled(stream: AuditStream = .app) -> AuditLog {
        AuditLog(stream: stream, writer: nil)
    }

    /// Whether records written here reach a file.
    public var isEnabled: Bool {
        writer != nil
    }

    // MARK: - Process-wide instance

    private static let installLock = NSLock()
    private nonisolated(unsafe) static var installed: AuditLog?

    /// The log for this process. A disabled instance until something calls
    /// ``bootstrap(stream:policy:)`` or ``install(_:)``.
    public static var shared: AuditLog {
        installLock.lock()
        defer { installLock.unlock() }
        if let installed {
            return installed
        }
        let fallback = AuditLog.disabled()
        installed = fallback
        return fallback
    }

    /// Replaces the process-wide log. Tests use this to point at a spy.
    public static func install(_ log: AuditLog) {
        installLock.lock()
        installed = log
        installLock.unlock()
    }

    /// Restores the disabled default. Tests call this in teardown.
    public static func reset() {
        installLock.lock()
        installed = nil
        installLock.unlock()
    }

    /// Opens the real file-backed stream and installs it, then writes the
    /// `audit.stream_opened` marker.
    ///
    /// Returns `false` and installs the disabled log when the stream cannot
    /// be opened — the expected case being a non-root process reaching for
    /// the daemon stream, which must degrade quietly rather than take the
    /// process down.
    @discardableResult
    public static func bootstrap(
        stream: AuditStream,
        policy: AuditRotationPolicy = .standard
    ) -> Bool {
        do {
            let writer = try AuditLogWriter(stream: stream, policy: policy)
            install(AuditLog(stream: stream, writer: writer))
            writer.recordStreamOpened()
            return true
        } catch {
            let description = String(describing: error)
            auditLogger.error(
                "audit stream \(stream.rawValue, privacy: .public) unavailable: \(description, privacy: .public)"
            )
            install(AuditLog.disabled(stream: stream))
            return false
        }
    }

    // MARK: - Emission

    /// Writes one record.
    public func emit(
        _ event: AuditEventType,
        actor: AuditActor,
        from: String? = nil,
        to: String? = nil,
        detail: [String: AuditValue] = [:],
        at timestamp: Date = Date()
    ) {
        guard let writer else { return }
        writer.append(AuditRecord(
            stream: stream,
            timestamp: timestamp,
            actor: actor,
            event: event,
            from: from,
            to: to,
            detail: detail
        ))
    }

    /// Writes a record only when `to` differs from the last value seen for
    /// `key`. The first observation always writes, with `from` absent, so the
    /// log states the starting value of every tracked dimension instead of
    /// leaving a reader to infer it.
    ///
    /// - Returns: `true` when a record was written.
    @discardableResult
    public func emitIfChanged(
        key: String,
        to newValue: String,
        event: AuditEventType,
        actor: AuditActor,
        detail: [String: AuditValue] = [:],
        at timestamp: Date = Date()
    ) -> Bool {
        lock.lock()
        let previous = lastObserved[key]
        if previous == newValue {
            lock.unlock()
            return false
        }
        lastObserved[key] = newValue
        lock.unlock()

        emit(
            event,
            actor: actor,
            from: previous,
            to: newValue,
            detail: detail,
            at: timestamp
        )
        return true
    }

    /// Records a value for `key` without writing anything, so the next
    /// ``emitIfChanged(key:to:event:actor:detail:at:)`` treats it as the
    /// baseline. Used when another record already states the value.
    public func seed(key: String, value: String) {
        lock.lock()
        lastObserved[key] = value
        lock.unlock()
    }
}
