import CryptoKit
import Foundation

public nonisolated enum BrowserNativeInstallation {
    public static let hostName = "studio.hypertext.curfew.browser"
    public static let developmentExtensionID = "loammdknmfbkjnckaeeagnmakinknbck"
    public static let developmentPublicKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnkryYyqIa7WjKAl8AMW9WssGLFlpm7HD7ThzyVexN7/Udrqdra5KpUPzXodE78gPCHMb9wPpguwgF/vD1impEdDEsDkzpIxN4aDWGxZxTDkxxWtmOntOS2YKWwGnbpz5myGO7gC/SSkc9zWOwSH8q6HbzWys0gaSJFNparL6kk+2COd/MUXwG88FYfqDgehlPn61LLvBOtNHjI8k8f2OxZL0P9VjF4DospQpDTLzq40kSRQAlV6iEnQEYWeKtaR0XgWtfDYM8x6phmprONuAE1xhbWAtZ+xZYB2HwOsE2zTwKBMUqOgcZRBoq1ShYvYLWv9rAF6MjjSsk8TOwVVnrwIDAQAB"

    public static func extensionID(publicKey: String) throws -> String {
        guard let data = Data(base64Encoded: publicKey),
              !data.isEmpty else { throw BrowserNativeError.invalidIdentity }
        return SHA256.hash(data: data).prefix(16).flatMap { [$0 >> 4, $0 & 15] }
            .map { String(UnicodeScalar(Int($0) + 97)!) }.joined()
    }

    public static func origin(extensionID: String) throws -> String {
        guard extensionID.utf8.count == 32,
              extensionID.utf8.allSatisfy({ (97 ... 112).contains($0) }) else {
            throw BrowserNativeError.invalidIdentity
        }
        return "chrome-extension://\(extensionID)/"
    }

    public static func validateCaller(_ caller: String, extensionID: String) throws -> Bool {
        guard try caller == origin(extensionID: extensionID)
        else { throw BrowserNativeError.unauthorizedCaller }
        return true
    }

    public static func manifestURL(home: URL) -> URL {
        home
            .appendingPathComponent(
                "Library/Application Support/Google/Chrome/NativeMessagingHosts"
            )
            .appendingPathComponent("\(hostName).json")
    }

    @discardableResult
    public static func install(
        extensionID: String,
        executable: URL,
        home: URL = SharedPaths.userHomeDirectory
    ) throws -> URL {
        let allowedOrigin = try origin(extensionID: extensionID)
        guard executable.isFileURL,
              executable.path.hasPrefix("/") else { throw BrowserNativeError.invalidIdentity }
        let manifest: [String: Any] = [
            "name": hostName, "description": "Curfew task browser policy", "path": executable.path,
            "type": "stdio", "allowed_origins": [allowedOrigin]
        ]
        let url = manifestURL(home: home)
        try BrowserNativeFiles.write(
            JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]),
            to: url
        )
        return url
    }

    public static func removeManifest(home: URL, executable: URL) throws {
        let url = manifestURL(home: home)
        guard let data = try BrowserNativeFiles.read(url),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["name"] as? String == hostName,
              object["path"] as? String == executable.path
        else { return }
        // Chrome has one manifest per host name. A dev uninstall must preserve
        // the manifest when the user has since installed the production app.
        try FileManager.default.removeItem(at: url)
    }
}
