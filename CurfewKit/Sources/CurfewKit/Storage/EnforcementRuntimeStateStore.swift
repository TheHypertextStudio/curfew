import Foundation

/// The main actor owns writes. An omitted URL keeps injected tests and demos off user storage.
public final class EnforcementRuntimeStateStore {
    public let recordURL: URL?
    private var memoryState: EnforcementRuntimeState?
    private let afterPersist: (() throws -> Void)?
    private static let maximumBytes = 65536

    public init(recordURL: URL? = nil, afterPersist: (() throws -> Void)? = nil) {
        self.recordURL = recordURL
        self.afterPersist = afterPersist
    }

    public static func production() -> EnforcementRuntimeStateStore {
        EnforcementRuntimeStateStore(
            recordURL: SharedPaths.applicationSupport
                .appendingPathComponent("enforcement-runtime.json")
        )
    }

    public func load() throws -> EnforcementRuntimeState? {
        guard let recordURL else { return memoryState }
        guard let data = try BoundedRegularFileReader.read(
            recordURL,
            maximumBytes: Self.maximumBytes
        )
        else { return nil }
        let state = try JSONDecoder().decode(EnforcementRuntimeState.self, from: data)
        try validate(state)
        return state
    }

    public func save(_ state: EnforcementRuntimeState) throws {
        try validate(state)
        let data = try JSONEncoder().encode(state)
        guard data.count <= Self.maximumBytes else { throw BoundedRegularFileReadError.tooLarge }
        guard let recordURL else {
            memoryState = state
            try afterPersist?()
            return
        }
        // Private bytes and the rename must reach disk before a grant takes effect.
        try BreakGlassPrivateFileWriter.write(data, to: recordURL, replaceExisting: true)
        try afterPersist?()
    }

    private func validate(_ state: EnforcementRuntimeState) throws {
        let counters = [
            state.extensionMinutes,
            state.snoozeMinutes,
            state.extensionUses,
            state.overrideUses
        ]
        let dates = [
            state.extensionResetBoundary,
            state.overrideResetBoundary,
            state.overrideUntil,
            state.mcpReceiptTrackingStartedAt
        ]
        let receipts = state.mcpGrantReceipts ?? []
        let legacy = state.legacyMCPGrantRequestIDs ?? []
        guard [1, 2].contains(state.version), !state.dayToken.isEmpty,
              counters.allSatisfy({ (0 ... 1_000_000).contains($0) }),
              dates.compactMap(\.self).allSatisfy(\.timeIntervalSince1970.isFinite),
              receipts.allSatisfy(\.isValid),
              Set(receipts.map(\.requestID)).count == receipts.count,
              Set(legacy).count == legacy.count,
              Set(legacy).isDisjoint(with: receipts.map(\.requestID)),
              state.version == 2 || (receipts.isEmpty && legacy.isEmpty &&
                  state.mcpReceiptTrackingStartedAt == nil)
        else {
            throw CocoaError(.coderReadCorrupt)
        }
    }
}
