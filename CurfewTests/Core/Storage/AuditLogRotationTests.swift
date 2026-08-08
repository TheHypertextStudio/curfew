@testable import Curfew
import Foundation
import Testing

/// Rotation, retention, and the per-stream separation that lets the app and
/// the root daemon both record during one lockout.
///
/// Split from ``AuditLogWriterTests`` to stay inside the type-body budget;
/// that suite covers append semantics and chain continuity.
struct AuditLogRotationTests {
    private func record(
        _ event: AuditEventType = .phaseChanged,
        stream: AuditStream = .app,
        detail: [String: AuditValue] = [:]
    ) -> AuditRecord {
        AuditRecord(
            stream: stream,
            timestamp: Date(timeIntervalSince1970: 1_764_000_000),
            actor: .app,
            event: event,
            detail: detail
        )
    }

    // MARK: - Rotation

    @Test("The active segment rotates once the size cap would be exceeded")
    func rotatesAtSizeCap() throws {
        let writer = try AuditTestSupport.makeWriter(
            label: "rotate",
            policy: AuditRotationPolicy(
                maxSegmentBytes: 700,
                maxRotatedSegments: 3,
                retentionDays: 90
            )
        )
        for index in 0 ..< 20 {
            writer.append(record(detail: ["index": .int(index)]))
        }

        #expect(FileManager.default.fileExists(atPath: writer.rotatedFileURL(index: 1).path))
        let activeBytes = try Data(contentsOf: writer.activeFileURL).count
        #expect(activeBytes <= 700 + 400)
    }

    @Test("Rotation keeps at most maxRotatedSegments files behind the active one")
    func rotationEnforcesSegmentCap() throws {
        let writer = try AuditTestSupport.makeWriter(
            label: "cap",
            policy: AuditRotationPolicy(
                maxSegmentBytes: 400,
                maxRotatedSegments: 2,
                retentionDays: 90
            )
        )
        for index in 0 ..< 60 {
            writer.append(record(detail: ["index": .int(index)]))
        }

        let manager = FileManager.default
        #expect(manager.fileExists(atPath: writer.rotatedFileURL(index: 1).path))
        #expect(manager.fileExists(atPath: writer.rotatedFileURL(index: 2).path))
        #expect(manager.fileExists(atPath: writer.rotatedFileURL(index: 3).path) == false)
    }

    @Test("Rotation writes a marker naming the segment it rolled into")
    func rotationIsRecorded() throws {
        let writer = try AuditTestSupport.makeWriter(
            label: "marker",
            policy: AuditRotationPolicy(
                maxSegmentBytes: 500,
                maxRotatedSegments: 3,
                retentionDays: 90
            )
        )
        for index in 0 ..< 12 {
            writer.append(record(detail: ["index": .int(index)]))
        }

        let rotationMarkers = AuditTestSupport.records(in: writer.activeFileURL)
            .filter { $0["event"] as? String == "audit.rotated" }
        let marker = try #require(rotationMarkers.first)
        let detail = try #require(marker["detail"] as? [String: Any])
        #expect((detail["rotatedTo"] as? String)?.hasSuffix(".1.jsonl") == true)
    }

    @Test("The hash chain spans a rotation, so a deleted segment shows as a break")
    func chainSpansRotation() throws {
        let writer = try AuditTestSupport.makeWriter(
            label: "span",
            policy: AuditRotationPolicy(
                maxSegmentBytes: 500,
                maxRotatedSegments: 3,
                retentionDays: 90
            )
        )
        for index in 0 ..< 12 {
            writer.append(record(detail: ["index": .int(index)]))
        }

        let rotated = AuditTestSupport.lines(of: writer.rotatedFileURL(index: 1))
        let active = AuditTestSupport.lines(of: writer.activeFileURL)
        let lastRotatedLine = try #require(rotated.last)
        let firstActiveLine = try #require(active.first)
        let lastRotatedHash = try #require(AuditLineEncoder.hash(inLine: lastRotatedLine))
        let firstActive = try #require(AuditTestSupport.parse(firstActiveLine))
        #expect(firstActive["prev"] as? String == lastRotatedHash)
    }

    @Test("Rotated segments past the retention window are deleted at the next rotation")
    func retentionPrunesOldSegments() throws {
        let directory = try AuditTestSupport.makeDirectory(label: "retention")
        let manager = FileManager.default
        let writer = try AuditLogWriter(
            stream: .app,
            directory: directory,
            baseName: "curfew-retention",
            policy: AuditRotationPolicy(
                maxSegmentBytes: 400,
                maxRotatedSegments: 3,
                retentionDays: 30
            ),
            filePermissions: 0o600
        )

        // Plant an expired segment in the slot rotation is about to reach.
        // Pruning runs at rotation time only, by design — Curfew never spins a
        // background sweeper for the audit log.
        let expired = writer.rotatedFileURL(index: 3)
        try Data("stale\n".utf8).write(to: expired)
        try manager.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60 * 86400)],
            ofItemAtPath: expired.path
        )
        #expect(manager.fileExists(atPath: expired.path))

        for index in 0 ..< 12 {
            writer.append(record(detail: ["index": .int(index)]))
        }

        // The expired file is gone rather than having been shifted along, and
        // a fresh segment took the slot rotation just filled.
        #expect(manager.fileExists(atPath: writer.rotatedFileURL(index: 1).path))
        let contents = (try? Data(contentsOf: expired))
            .flatMap { String(bytes: $0, encoding: .utf8) }
        #expect(contents?.contains("stale") != true)
    }

    // MARK: - Multi-writer separation

    @Test("The app and daemon streams resolve to different files in different trees")
    func streamsAreSeparateFiles() {
        let appFile = AuditLogPaths.activeFile(for: .app)
        let daemonFile = AuditLogPaths.activeFile(for: .daemon)
        #expect(appFile != daemonFile)
        #expect(appFile.lastPathComponent == "curfew-app.jsonl")
        #expect(daemonFile.lastPathComponent == "curfew-daemon.jsonl")
        #expect(daemonFile.path.hasPrefix("/Library/Logs/Curfew"))
        #expect(appFile.path.contains("/Library/Logs/Curfew"))
        #expect(appFile.path.hasPrefix("/Library/Logs/") == false)
    }

    @Test("Two writers for different streams never touch each other's file or chain")
    func concurrentStreamsDoNotInterleave() throws {
        let directory = try AuditTestSupport.makeDirectory(label: "separation")
        let appWriter = try AuditLogWriter(
            stream: .app,
            directory: directory,
            baseName: "curfew-app",
            filePermissions: 0o600
        )
        let daemonWriter = try AuditLogWriter(
            stream: .daemon,
            directory: directory,
            baseName: "curfew-daemon",
            filePermissions: 0o600
        )

        // Interleave writes the way a live lockout would.
        appWriter.append(record(.lockoutStarted))
        daemonWriter.append(record(.daemonStarted, stream: .daemon))
        appWriter.append(record(.phaseChanged))
        daemonWriter.append(record(.daemonHeartbeatStale, stream: .daemon))

        let appRecords = AuditTestSupport.records(in: appWriter.activeFileURL)
        let daemonRecords = AuditTestSupport.records(in: daemonWriter.activeFileURL)
        #expect(appRecords.count == 2)
        #expect(daemonRecords.count == 2)
        #expect(appRecords.allSatisfy { $0["stream"] as? String == "app" })
        #expect(daemonRecords.allSatisfy { $0["stream"] as? String == "daemon" })
        // Each stream numbers itself from 1 — sequence is per-stream, not global.
        #expect(appRecords.compactMap { $0["seq"] as? Int } == [1, 2])
        #expect(daemonRecords.compactMap { $0["seq"] as? Int } == [1, 2])
        // Neither chain references the other.
        #expect(appRecords.first?["prev"] as? String == auditGenesisHash)
        #expect(daemonRecords.first?["prev"] as? String == auditGenesisHash)
    }

    @Test("The app stream is created private to the user")
    func appStreamIsUserOnly() throws {
        let writer = try AuditTestSupport.makeWriter(label: "perms")
        writer.append(record())
        let attributes = try FileManager.default.attributesOfItem(
            atPath: writer.activeFileURL.path
        )
        let mode = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(mode.int16Value == 0o600)
    }
}
