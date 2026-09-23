import AppKit
import Darwin
import Foundation

struct AccountRecoveryKeyDocument {
    static let suggestedFilename = "curfew-recovery-key.txt"

    let recoveryKey: String

    func write(to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".curfew-recovery-key-\(UUID().uuidString).tmp")
        let contents = Data("\(recoveryKey)\n".utf8)
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: contents,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporary.path
            )
            guard rename(temporary.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

@MainActor
enum AccountRecoveryKeyClipboard {
    static func copy(_ recoveryKey: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        guard pasteboard.setString(recoveryKey, forType: .string) else {
            return false
        }
        let changeCount = pasteboard.changeCount
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
            }
        }
        return true
    }
}
