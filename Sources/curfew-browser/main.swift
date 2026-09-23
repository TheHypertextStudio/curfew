import CurfewKit
import Darwin
import Foundation

@main
enum CurfewBrowserMain {
    static func main() async {
        do {
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            let bundleURL = executable.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
            guard let bundle = Bundle(url: bundleURL), CommandLine.arguments.count == 2 else {
                throw BrowserNativeError.invalidIdentity
            }
            let flavor = CurfewFlavor.resolve(
                environment: [:],
                bundleIdentifier: bundle.bundleIdentifier
            )
            guard flavor != .studioDevelopment else { throw BrowserNativeError.invalidIdentity }
            setenv("CURFEW_FLAVOR", flavor.environmentValue, 1)
            let extensionID = flavor == .development ? BrowserNativeInstallation
                .developmentExtensionID
                : bundle.object(forInfoDictionaryKey: "CurfewBrowserExtensionID") as? String ?? ""
            let caller = CommandLine.arguments[1]
            _ = try BrowserNativeInstallation.validateCaller(caller, extensionID: extensionID)
            let host = BrowserNativeHost(store: BrowserNativeStore(), callerOrigin: caller)
            while let data = try readMessage() {
                let response: BrowserNativeResponse
                do {
                    response = try await host.handle(BrowserNativeRequest.decode(data))
                } catch {
                    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    var invalid = BrowserNativeResponse(
                        requestID: String((object?["requestId"] as? String ?? "").prefix(128)),
                        type: BrowserNativeRequest
                            .MessageType(rawValue: object?["type"] as? String ?? "") ?? .getPolicy
                    )
                    invalid.error = "invalid_request"
                    response = invalid
                }
                try writeResponse(response)
            }
        } catch {
            // Errors may embed the destination or private filesystem names.
            // Chrome only needs a bounded protocol error and an exit status.
            try? FileHandle.standardError
                .write(contentsOf: Data("Curfew browser host stopped.\n".utf8))
            exit(1)
        }
    }

    private static func readMessage() throws -> Data? {
        guard let header = try readExactly(4, allowEOF: true) else { return nil }
        let count = header.withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self)) }
        guard count <= BrowserNativeFraming.maximumInboundBytes
        else { throw BrowserNativeError.messageTooLarge }
        return try readExactly(count, allowEOF: false)
    }

    private static func readExactly(_ count: Int, allowEOF: Bool) throws -> Data? {
        var result = Data()
        while result.count < count {
            let chunk = try FileHandle.standardInput.read(upToCount: min(
                16384,
                count - result.count
            )) ?? Data()
            if chunk.isEmpty {
                if allowEOF, result.isEmpty {
                    return nil
                }
                throw BrowserNativeError.invalidRequest
            }
            result.append(chunk)
        }
        return result
    }

    private static func writeResponse(_ response: BrowserNativeResponse) throws {
        var data = try BrowserNativeJSON.encode(response)
        if data.count > BrowserNativeFraming.maximumOutboundBytes {
            var bounded = BrowserNativeResponse(requestID: response.requestID, type: response.type)
            bounded.error = "response_too_large"
            data = try BrowserNativeJSON.encode(bounded)
        }
        try FileHandle.standardOutput.write(contentsOf: BrowserNativeFraming.encode(data))
    }
}
