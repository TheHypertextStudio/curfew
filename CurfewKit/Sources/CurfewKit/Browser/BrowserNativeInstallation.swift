import CryptoKit
import Darwin
import Foundation

public nonisolated enum BrowserNativeInstallation {
    public static let hostName = "studio.hypertext.curfew.browser"
    public static func hostName(for flavor: CurfewFlavor) -> String {
        "studio.hypertext.curfew\(flavor.identifierSuffix).browser"
    }

    public static func browserDirectory(home: URL, flavor: CurfewFlavor) -> URL {
        home.appendingPathComponent(
            "Library/Application Support/Curfew\(flavor.displaySuffix)/browser",
            isDirectory: true
        )
    }

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

    public static func manifestURL(home: URL, flavor: CurfewFlavor = .current) -> URL {
        home
            .appendingPathComponent(
                "Library/Application Support/Google/Chrome/NativeMessagingHosts"
            )
            .appendingPathComponent("\(hostName(for: flavor)).json")
    }

    @discardableResult
    public static func install(
        extensionID: String,
        executable: URL,
        home: URL = SharedPaths.userHomeDirectory,
        flavor: CurfewFlavor = .current
    ) throws -> URL {
        let allowedOrigin = try origin(extensionID: extensionID)
        guard executable.isFileURL,
              executable.path.hasPrefix("/") else { throw BrowserNativeError.invalidIdentity }
        var metadata = stat()
        guard lstat(executable.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_mode & 0o111 != 0,
              access(executable.path, X_OK) == 0
        else { throw BrowserNativeError.invalidIdentity }
        let manifest: [String: Any] = [
            "name": hostName(for: flavor), "description": "Curfew task browser policy",
            "path": executable.path,
            "type": "stdio", "allowed_origins": [allowedOrigin]
        ]
        let url = manifestURL(home: home, flavor: flavor)
        try BrowserNativeFiles.write(
            JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]),
            to: url
        )
        try BrowserNativeStore(directory: browserDirectory(home: home, flavor: flavor)).activate()
        return url
    }

    public static func removeManifest(
        home: URL,
        executable: URL,
        flavor: CurfewFlavor = .current
    ) throws {
        let url = manifestURL(home: home, flavor: flavor)
        guard let data = try BrowserNativeFiles.read(url),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["name"] as? String == hostName(for: flavor),
              object["path"] as? String == executable.path
        else { return }
        // The executable check also preserves a newer installation of this
        // same flavor when uninstall runs from an older app location.
        try BrowserNativeStore(directory: browserDirectory(home: home, flavor: flavor)).deactivate()
        try FileManager.default.removeItem(at: url)
    }
}
