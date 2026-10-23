import Darwin
import Foundation

/// The main actor owns writes. An omitted URL keeps injected tests and demos off user storage.
public final class EnforcementRuntimeStateStore {
    public let recordURL: URL?
    private var memoryState: EnforcementRuntimeState?

    public init(recordURL: URL? = nil) {
        self.recordURL = recordURL
    }

    public static func production() -> EnforcementRuntimeStateStore {
        EnforcementRuntimeStateStore(
            recordURL: SharedPaths.applicationSupport
                .appendingPathComponent("enforcement-runtime.json")
        )
    }

    public func load() throws -> EnforcementRuntimeState? {
        guard let recordURL else { return memoryState }
        let data: Data
        do {
            data = try Data(contentsOf: recordURL)
        } catch {
            let cocoaError = error as NSError
            let underlying = cocoaError.userInfo[NSUnderlyingErrorKey] as? NSError
            if cocoaError.domain == NSCocoaErrorDomain,
               cocoaError.code == CocoaError.fileReadNoSuchFile.rawValue,
               underlying?.domain == NSPOSIXErrorDomain, underlying?.code == Int(ENOENT) {
                return nil
            }
            throw error
        }
        let state = try JSONDecoder().decode(EnforcementRuntimeState.self, from: data)
        try validate(state)
        return state
    }

    public func save(_ state: EnforcementRuntimeState) throws {
        try validate(state)
        guard let recordURL else {
            memoryState = state
            return
        }
        let directory = recordURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: recordURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: recordURL.path
        )
        let file = try FileHandle(forWritingTo: recordURL)
        defer { try? file.close() }
        try file.synchronize()
        // The rename must reach disk as well as the bytes before a grant takes effect.
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0
        else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private func validate(_ state: EnforcementRuntimeState) throws {
        let counters = [
            state.extensionMinutes,
            state.snoozeMinutes,
            state.extensionUses,
            state.overrideUses
        ]
        let dates = [state.extensionResetBoundary, state.overrideResetBoundary, state.overrideUntil]
        guard state.version == 1, !state.dayToken.isEmpty,
              counters.allSatisfy({ (0 ... 1_000_000).contains($0) }),
              dates.compactMap(\.self).allSatisfy(\.timeIntervalSince1970.isFinite)
        else {
            throw CocoaError(.coderReadCorrupt)
        }
    }
}
