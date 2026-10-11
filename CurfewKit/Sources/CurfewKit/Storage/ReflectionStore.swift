import Foundation
import OSLog
import SQLite3

/// Sentinel pointer passed as `pvarg` to SQLite bind functions so the library
/// copies the caller's string rather than retaining the pointer. SQLite's
/// default (`SQLITE_STATIC`) assumes the buffer outlives the statement, which
/// is unsafe for Swift `String.withCString` lifetimes.
private let sqliteTransient = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)

/// SQLite-backed append-only log of ``Reflection``.
///
/// Storage mirrors ``ActivityStore`` deliberately: a single `reflections`
/// table keyed on `timestamp`, WAL journalling, and a serial dispatch queue
/// fronting every SQLite call so the store is thread-safe by construction and
/// can be invoked from any queue.
///
/// Reflections live in their own database rather than the activity `events`
/// table because their payload is a *structured set* of typed answers, not a
/// single scalar — the answer array is serialised to JSON in the `answers`
/// column. The activity log still carries a lightweight
/// ``ActivityEventKind/reflectionRecorded`` marker so timelines and rollups
/// can note that a reflection happened without reaching into this store.
///
/// Intended usage is a single long-lived instance held by `CurfewAppModel`
/// for the lifetime of the process; the CLI / MCP tools open a short-lived
/// read instance against the same file (``SharedPaths/reflectionDatabase``).
public final class ReflectionStore {
    /// On-disk path to the SQLite file. Exposed so tests can assert the
    /// database lives where we expect and so export tooling can reopen it
    /// without going through this class.
    public let databaseURL: URL

    /// Raw SQLite handle. `nil` only briefly during init failure paths
    /// (before `throw`) and after `deinit`. Every method guards on this
    /// before touching SQLite.
    private var handle: OpaquePointer?

    /// Serial queue wrapping every SQLite interaction — keeps error handling
    /// in one place and avoids `@unchecked Sendable` on the pointer.
    private let queue = DispatchQueue(label: "studio.hypertext.curfew.reflection-store")

    /// JSON coders for the `answers` column. Held on the instance so they are
    /// configured once; reflection writes are rare so the cost is negligible.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Opens (or creates) the reflection database at
    /// `<directory>/reflections.sqlite3`. The directory must already exist.
    public convenience init(directory: URL) throws {
        try self.init(databaseURL: directory.appendingPathComponent("reflections.sqlite3"))
    }

    /// Opens (or creates) the SQLite file at `databaseURL`. The parent
    /// directory must exist; the file itself is created if absent. Throws
    /// ``ReflectionStoreError/couldNotOpenDatabase`` when SQLite refuses to
    /// open the path (missing parent, disk full, permission).
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
            throw ReflectionStoreError.couldNotOpenDatabase
        }
        self.handle = handle
        try installSchema(on: handle)
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    /// Persists one reflection. Re-appending a reflection with the same `id`
    /// raises ``ReflectionStoreError/duplicateReflectionID``.
    public func append(_ reflection: Reflection) throws {
        let answersJSON = try encodeAnswers(reflection.answers)
        try queue.sync {
            try runInsert(reflection, answersJSON: answersJSON)
        }
    }

    /// Returns reflections whose `timestamp` falls within `range` (inclusive),
    /// ordered ascending. Pass `.distantPast ... .distantFuture` to read the
    /// full log.
    public func reflections(in range: ClosedRange<Date>) throws -> [Reflection] {
        try queue.sync {
            try runFetch(from: range.lowerBound, through: range.upperBound)
        }
    }

    /// Deletes every reflection older than `olderThan` seconds relative to
    /// `now`. Mirrors ``ActivityStore``'s retention trim so callers can apply
    /// the same 52-week window on day rollover.
    public func trimReflections(olderThan olderThanSeconds: TimeInterval, now: Date) throws {
        try queue.sync {
            try runTrim(olderThanSeconds: olderThanSeconds, now: now)
        }
    }

    // MARK: - SQLite plumbing

    private func installSchema(on handle: OpaquePointer) throws {
        // WAL + NORMAL synchronous so a power loss or force-kill mid-write
        // rolls back the in-flight row rather than leaving a half-written
        // record — matching ActivityStore's durability posture.
        try exec("PRAGMA journal_mode = WAL;", on: handle)
        try exec("PRAGMA synchronous = NORMAL;", on: handle)
        try exec(
            """
            CREATE TABLE IF NOT EXISTS reflections (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                gate TEXT NOT NULL,
                answers TEXT NOT NULL
            );
            """,
            on: handle
        )
        try exec(
            "CREATE INDEX IF NOT EXISTS reflections_timestamp_idx ON reflections(timestamp);",
            on: handle
        )
    }

    private func exec(_ sql: String, on handle: OpaquePointer) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &errmsg)
        guard status == SQLITE_OK else {
            let message = errmsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errmsg)
            throw ReflectionStoreError.sqliteFailure(message: message)
        }
    }

    /// Runs `body` with a prepared statement for `sql`, finalising it on
    /// return. Centralises the `prepare → defer finalize` dance.
    private func prepared<T>(
        _ sql: String,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        guard let handle else {
            throw ReflectionStoreError.storeClosed
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ReflectionStoreError.sqliteFailure(message: lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        return try body(stmt)
    }

    private func runInsert(_ reflection: Reflection, answersJSON: String) throws {
        let sql = """
        INSERT INTO reflections (id, timestamp, gate, answers)
        VALUES (?, ?, ?, ?);
        """
        try prepared(sql) { stmt in
            sqlite3_bind_text(stmt, 1, reflection.id.uuidString, -1, sqliteTransient)
            sqlite3_bind_double(stmt, 2, reflection.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, reflection.gate.rawValue, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 4, answersJSON, -1, sqliteTransient)

            let status = sqlite3_step(stmt)
            guard status == SQLITE_DONE else {
                if status == SQLITE_CONSTRAINT {
                    throw ReflectionStoreError.duplicateReflectionID
                }
                throw ReflectionStoreError.sqliteFailure(message: lastErrorMessage())
            }
        }
    }

    private func runFetch(from: Date, through: Date) throws -> [Reflection] {
        let sql = """
        SELECT id, timestamp, gate, answers
        FROM reflections
        WHERE timestamp BETWEEN ? AND ?
        ORDER BY timestamp ASC;
        """
        return try prepared(sql) { stmt in
            sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, through.timeIntervalSince1970)

            var reflections: [Reflection] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let reflection = try decodeRow(stmt) {
                    reflections.append(reflection)
                }
            }
            return reflections
        }
    }

    private func runTrim(olderThanSeconds: TimeInterval, now: Date) throws {
        let cutoff = now.addingTimeInterval(-olderThanSeconds).timeIntervalSince1970
        try prepared("DELETE FROM reflections WHERE timestamp < ?;") { stmt in
            sqlite3_bind_double(stmt, 1, cutoff)
            let status = sqlite3_step(stmt)
            guard status == SQLITE_DONE else {
                throw ReflectionStoreError.sqliteFailure(message: lastErrorMessage())
            }
        }
    }

    private func decodeRow(_ stmt: OpaquePointer) throws -> Reflection? {
        guard
            let idPointer = sqlite3_column_text(stmt, 0),
            let gatePointer = sqlite3_column_text(stmt, 2),
            let answersPointer = sqlite3_column_text(stmt, 3)
        else {
            return nil
        }
        let idString = String(cString: idPointer)
        guard let id = UUID(uuidString: idString) else {
            throw ReflectionStoreError.corruptRow(reason: "invalid UUID \(idString)")
        }
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        let gateString = String(cString: gatePointer)
        guard let gate = ReflectionGate(rawValue: gateString) else {
            throw ReflectionStoreError.corruptRow(reason: "unknown gate \(gateString)")
        }
        let answersString = String(cString: answersPointer)
        let answers = try decodeAnswers(answersString)
        return Reflection(id: id, timestamp: timestamp, gate: gate, answers: answers)
    }

    private func encodeAnswers(_ answers: [ReflectionAnswer]) throws -> String {
        guard
            let data = try? encoder.encode(answers),
            let json = String(data: data, encoding: .utf8)
        else {
            throw ReflectionStoreError.corruptRow(reason: "answers not encodable")
        }
        return json
    }

    private func decodeAnswers(_ json: String) throws -> [ReflectionAnswer] {
        guard let data = json.data(using: .utf8) else {
            throw ReflectionStoreError.corruptRow(reason: "answers not utf8")
        }
        do {
            return try decoder.decode([ReflectionAnswer].self, from: data)
        } catch {
            throw ReflectionStoreError.corruptRow(reason: "answers decode failed")
        }
    }

    private func lastErrorMessage() -> String {
        guard let handle, let pointer = sqlite3_errmsg(handle) else {
            return "unknown"
        }
        return String(cString: pointer)
    }
}

/// Failure modes for ``ReflectionStore``. Named around caller intent rather
/// than raw SQLite status codes, mirroring ``ActivityStoreError``.
public enum ReflectionStoreError: Error, Equatable {
    /// `sqlite3_open_v2` failed to open or create the database file.
    case couldNotOpenDatabase

    /// `sqlite3_prepare_v2` / `sqlite3_exec` / `sqlite3_step` returned a
    /// non-OK status. `message` is SQLite's own last-error string.
    case sqliteFailure(message: String)

    /// Insert collided with an existing `id`. Only expected in tests;
    /// production inserts carry fresh UUIDs.
    case duplicateReflectionID

    /// Row decoded at the SQL level but failed Swift-side validation (invalid
    /// UUID, unknown gate, or undecodable answers JSON).
    case corruptRow(reason: String)

    /// Operation attempted after the store's `handle` went nil — only
    /// possible if the initialiser partially failed and we hold a stale
    /// reference.
    case storeClosed
}
