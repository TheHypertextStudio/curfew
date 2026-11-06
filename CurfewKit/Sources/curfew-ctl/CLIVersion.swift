import Foundation

enum CLIVersion {
    static let development = "0.0.17-beta.1"

    static var current: String {
        guard let executable = try? CLIExecutable.location() else { return development }
        return resolve(executableURL: executable)
    }

    static func resolve(executableURL: URL) -> String {
        let resources = executableURL.deletingLastPathComponent()
        guard resources.lastPathComponent == "Resources",
              resources.deletingLastPathComponent().lastPathComponent == "Contents" else {
            return development
        }
        let infoURL = resources.deletingLastPathComponent().appendingPathComponent("Info.plist")
        guard let bytes = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: bytes, format: nil)
              as? [String: Any],
              let version = info["CFBundleShortVersionString"] as? String,
              version.range(
                  of: #"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"#,
                  options: .regularExpression
              ) != nil else {
            return development
        }
        return version
    }
}
