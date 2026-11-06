@testable import curfew_ctl
import CurfewKit
import Foundation
import SQLite3
import Testing

struct CLIReadTests {
    @Test("Empty activity and reflection exports remain JSON arrays")
    func emptyExports() throws {
        let activity = try JSONSerialization
            .jsonObject(with: ActivityCommand.jsonData(events: [])) as? [String: Any]
        let reflections = try JSONSerialization
            .jsonObject(with: ReflectionCommand.jsonData(reflections: [])) as? [String: Any]
        #expect((activity?["events"] as? [Any])?.isEmpty == true)
        #expect((reflections?["reflections"] as? [Any])?.isEmpty == true)
    }

    @Test("Unreadable activity is an error instead of an empty successful result")
    func corruptStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("activity.sqlite3")
        try Data("corrupt sqlite".utf8).write(to: database)
        #expect(throws: (any Error).self) {
            _ = try openActivityStore(at: database)
        }
    }

    @Test("Absent activity store stays absent")
    func missingStore() throws {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        #expect(try openActivityStore(at: database) == nil)
        #expect(!FileManager.default.fileExists(atPath: database.path))
    }

    @Test("Inspection rejects empty databases without creating a schema")
    func emptyDatabases() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["activity.sqlite3", "reflections.sqlite3"] {
            let url = directory.appendingPathComponent(name)
            try Data().write(to: url)
            #expect(throws: (any Error).self) {
                if name == "activity.sqlite3" {
                    _ = try openActivityStore(at: url)
                } else {
                    _ = try openReflectionStore(at: url)
                }
            }
            #expect(try Data(contentsOf: url).isEmpty)
        }
    }

    @Test("SQLite step failures cannot become a successful empty history", arguments: [false, true])
    func lockedDatabase(reflections: Bool) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("database.sqlite3")
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        let database = try #require(handle)
        defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil); sqlite3_close(database) }
        let table = reflections ? "reflections" : "events"
        let columns = reflections
            ? "id TEXT, timestamp REAL, gate TEXT, answers TEXT"
            : "id TEXT, timestamp REAL, gate_kind TEXT, kind TEXT, minutes_value INTEGER, note TEXT"
        let schema = "CREATE TABLE \(table) (\(columns))"
        #expect(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK)
        let read: () throws -> Void
        if reflections {
            let store = try #require(try openReflectionStore(at: url))
            read = { _ = try store.reflections(in: .distantPast ... .distantFuture) }
        } else {
            let store = try #require(try openActivityStore(at: url))
            read = { _ = try store.events(in: .distantPast ... .distantFuture) }
        }
        #expect(sqlite3_exec(database, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
        #expect(throws: (any Error).self) { try read() }
    }

    @Test("Read-only inspection opens existing valid stores through macOS temporary paths")
    func validInspection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let activityURL = directory.appendingPathComponent("activity.sqlite3")
        let reflectionsURL = directory.appendingPathComponent("reflections.sqlite3")
        _ = try ActivityStore(databaseURL: activityURL)
        _ = try ReflectionStore(databaseURL: reflectionsURL)
        let activity = try #require(try openActivityStore(at: activityURL))
        let reflections = try #require(try openReflectionStore(at: reflectionsURL))
        #expect(try activity.events(in: .distantPast ... .distantFuture).isEmpty)
        #expect(try reflections.reflections(in: .distantPast ... .distantFuture).isEmpty)
    }
}
