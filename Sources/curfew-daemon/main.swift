import CurfewKit
import Foundation
import OSLog

private let daemonLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "privileged-daemon"
)

private let heartbeatURL = SharedPaths.privilegedApplicationSupport
    .appendingPathComponent(".daemon-alive")

private let heartbeatInterval: TimeInterval = 60

let fileManager = FileManager.default
let sentinelPath = SharedPaths.lockoutActiveSentinel.path

daemonLogger.info("curfew-daemon launched")

while fileManager.fileExists(atPath: sentinelPath) {
    do {
        let heartbeat = ISO8601DateFormatter().string(from: Date()).data(using: .utf8) ?? Data()
        try fileManager.createDirectory(
            at: heartbeatURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try heartbeat.write(to: heartbeatURL, options: .atomic)
    } catch {
        daemonLogger.error(
            "failed to update daemon heartbeat: \(error.localizedDescription, privacy: .public)"
        )
    }

    Thread.sleep(forTimeInterval: heartbeatInterval)
}

daemonLogger.info("curfew-daemon exiting because the lockout sentinel is absent")
