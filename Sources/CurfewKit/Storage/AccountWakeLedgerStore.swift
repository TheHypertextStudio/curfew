import Foundation

/// Atomic persistence for the last authenticated account wake state.
public struct AccountWakeLedgerStore {
    private let fileManager: FileManager
    public let recordURL: URL

    public init(
        fileManager: FileManager = .default,
        recordURL: URL = SharedPaths.accountWakeLedger
    ) {
        self.fileManager = fileManager
        self.recordURL = recordURL
    }

    public func load() -> AccountWakeLedger? {
        guard let data = try? Data(contentsOf: recordURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AccountWakeLedger.self, from: data)
    }

    public func save(_ ledger: AccountWakeLedger) throws {
        try fileManager.createDirectory(
            at: recordURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ledger).write(to: recordURL, options: .atomic)
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: recordURL.path) else { return }
        try fileManager.removeItem(at: recordURL)
    }
}
