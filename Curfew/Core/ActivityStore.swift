import Foundation
import OSLog
import SQLite3

/// Sentinel pointer passed as `pvarg` to SQLite bind functions so the
/// library copies the caller's string rather than retaining the pointer.
/// SQLite's default (`SQLITE_STATIC`) assumes the buffer outlives the
/// statement, which is unsafe for Swift `String.withCString` lifetimes.
private let sqliteTransient = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)

/// SQLite-backed append-only log of ``ActivityEvent``.
///
/// Storage model is a single `events` table rather than one-table-per-kind
/// because:
/// - Every query the UI and exports care about is "events in a time range
///   with optional kind filter" — SQLite handles that trivially with an
///   index on `timestamp`.
/// - Future gate kinds slot in by inserting rows with a different
///   `gate_kind`; no schema change.
///
/// The store is thread-safe by construction: every call takes the internal
/// serial queue before touching the SQLite handle. Callers can invoke from
/// any queue. Intended usage is a single long-lived instance held by
/// ``CurfewAppModel`` for the lifetime of the process.
public final class ActivityStore {
    /// On-disk path to the SQLite file. Exposed so tests can assert the
    /// database lives where we expect and so future export / backup
    /// tooling can read it without reopening through this class.
    public let databaseURL: URL

    /// Raw SQLite handle. `nil` only briefly during init failure paths
    /// (before `throw`) and after `deinit`. Every method guards on this
    /// before touching SQLite, rather than assuming validity.
    private var handle: OpaquePointer?

    /// Serial queue that wraps every SQLite interaction. SQLite itself can
    /// be compiled in serialised mode, but funnelling through a Swift
    /// queue keeps error handling + tracing in one place and avoids
    /// introducing `@unchecked Sendable` on the pointer.
    private let queue = DispatchQueue(label: "studio.hypertext.curfew.activity-store")

    /// Opens (or creates) the activity log database at
    /// `<directory>/activity.sqlite3`. The directory must already exist.
    public convenience init(directory: URL) throws {
        try self.init(databaseURL: directory.appendingPathComponent("activity.sqlite3"))
    }

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard status == SQLITE_OK, let handle else {
            if let handle {
                sqlite3_close(handle)
            }
            throw ActivityStoreError.couldNotOpenDatabase
        }
        self.handle = handle
        try installSchema(on: handle)
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    /// Persists one event. Re-appending an event with the same `id` raises
    /// ``ActivityStoreError/duplicateEventID``.
    public func append(_ event: ActivityEvent) throws {
        try queue.sync {
            try runInsert(event)
        }
    }

    /// Returns events whose `timestamp` falls within `range` (inclusive),
    /// ordered ascending. Pass `.distantPast ... .distantFuture` to read
    /// the full log.
    public func events(in range: ClosedRange<Date>) throws -> [ActivityEvent] {
        try queue.sync {
            try runFetch(from: range.lowerBound, through: range.upperBound)
        }
    }

    /// Deletes every event older than `olderThan` seconds relative to
    /// `now`. The recorder calls this on day rollover to enforce the
    /// 52-week retention window.
    public func trimEvents(olderThan olderThanSeconds: TimeInterval, now: Date) throws {
        try queue.sync {
            try runTrim(olderThanSeconds: olderThanSeconds, now: now)
        }
    }

    // MARK: - SQLite plumbing

    private func installSchema(on handle: OpaquePointer) throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS events (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                gate_kind TEXT NOT NULL,
                kind TEXT NOT NULL,
                minutes_value INTEGER,
                note TEXT
            );
            """,
            on: handle
        )
        try exec(
            "CREATE INDEX IF NOT EXISTS events_timestamp_idx ON events(timestamp);",
            on: handle
        )
    }

    private func exec(_ sql: String, on handle: OpaquePointer) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &errmsg)
        guard status == SQLITE_OK else {
            let message = errmsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errmsg)
            throw ActivityStoreError.sqliteFailure(message: message)
        }
    }

    /// Runs `body` with a prepared statement for `sql`, finalising it on
    /// return. Centralises the `prepare → defer finalize` dance so the
    /// three query methods below don't repeat it.
    private func prepared<T>(
        _ sql: String,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        guard let handle else {
            throw ActivityStoreError.storeClosed
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ActivityStoreError.sqliteFailure(message: lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        return try body(stmt)
    }

    private func runInsert(_ event: ActivityEvent) throws {
        let sql = """
        INSERT INTO events (id, timestamp, gate_kind, kind, minutes_value, note)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        try prepared(sql) { stmt in
            sqlite3_bind_text(stmt, 1, event.id.uuidString, -1, sqliteTransient)
            sqlite3_bind_double(stmt, 2, event.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, event.gateKind, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 4, event.kind.rawValue, -1, sqliteTransient)
            if let minutes = event.minutesValue {
                sqlite3_bind_int64(stmt, 5, Int64(minutes))
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            if let note = event.note {
                sqlite3_bind_text(stmt, 6, note, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(stmt, 6)
            }

            let status = sqlite3_step(stmt)
            guard status == SQLITE_DONE else {
                if status == SQLITE_CONSTRAINT {
                    throw ActivityStoreError.duplicateEventID
                }
                throw ActivityStoreError.sqliteFailure(message: lastErrorMessage())
            }
        }
    }

    private func runFetch(from: Date, through: Date) throws -> [ActivityEvent] {
        let sql = """
        SELECT id, timestamp, gate_kind, kind, minutes_value, note
        FROM events
        WHERE timestamp BETWEEN ? AND ?
        ORDER BY timestamp ASC;
        """
        return try prepared(sql) { stmt in
            sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, through.timeIntervalSince1970)

            var events: [ActivityEvent] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let event = try decodeRow(stmt) {
                    events.append(event)
                }
            }
            return events
        }
    }

    private func runTrim(olderThanSeconds: TimeInterval, now: Date) throws {
        let cutoff = now.addingTimeInterval(-olderThanSeconds).timeIntervalSince1970
        try prepared("DELETE FROM events WHERE timestamp < ?;") { stmt in
            sqlite3_bind_double(stmt, 1, cutoff)
            let status = sqlite3_step(stmt)
            guard status == SQLITE_DONE else {
                throw ActivityStoreError.sqliteFailure(message: lastErrorMessage())
            }
        }
    }

    private func decodeRow(_ stmt: OpaquePointer) throws -> ActivityEvent? {
        guard
            let idPointer = sqlite3_column_text(stmt, 0),
            let gateKindPointer = sqlite3_column_text(stmt, 2),
            let kindPointer = sqlite3_column_text(stmt, 3)
        else {
            return nil
        }
        let idString = String(cString: idPointer)
        guard let id = UUID(uuidString: idString) else {
            throw ActivityStoreError.corruptRow(reason: "invalid UUID \(idString)")
        }
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        let gateKind = String(cString: gateKindPointer)
        let kindString = String(cString: kindPointer)
        guard let kind = ActivityEventKind(rawValue: kindString) else {
            throw ActivityStoreError.corruptRow(reason: "unknown kind \(kindString)")
        }
        let minutesValue: Int? = sqlite3_column_type(stmt, 4) == SQLITE_NULL
            ? nil
            : Int(sqlite3_column_int64(stmt, 4))
        let note: String? = sqlite3_column_type(stmt, 5) == SQLITE_NULL
            ? nil
            : sqlite3_column_text(stmt, 5).map { String(cString: $0) }
        return ActivityEvent(
            id: id,
            timestamp: timestamp,
            gateKind: gateKind,
            kind: kind,
            minutesValue: minutesValue,
            note: note
        )
    }

    private func lastErrorMessage() -> String {
        guard let handle, let pointer = sqlite3_errmsg(handle) else {
            return "unknown"
        }
        return String(cString: pointer)
    }
}

/// Failure modes for ``ActivityStore``. Cases are named around caller
/// intent rather than exposing raw SQLite status codes — callers don't
/// need to branch on SQLite internals.
public enum ActivityStoreError: Error, Equatable {
    /// `sqlite3_open_v2` failed to open or create the database file.
    case couldNotOpenDatabase

    /// `sqlite3_prepare_v2` / `sqlite3_exec` / `sqlite3_step` returned a
    /// non-OK status. `message` is SQLite's own last-error string,
    /// suitable for logging.
    case sqliteFailure(message: String)

    /// Insert collided with an existing `id`. Only expected during tests;
    /// production inserts always carry fresh UUIDs.
    case duplicateEventID

    /// Row decoded successfully at the SQL level but failed Swift-side
    /// validation (invalid UUID, unknown kind enum value). Reason is a
    /// short debug string, not a user-visible message.
    case corruptRow(reason: String)

    /// Operation attempted after the store's `handle` went nil — only
    /// possible if the initialiser partially failed and we hold a stale
    /// reference.
    case storeClosed
}
