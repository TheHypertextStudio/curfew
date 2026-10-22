import CurfewKit
import Foundation

/// Metadata and request receipts are distinct from screensaver host acceptance.
@MainActor
struct RestScreenSaverInstallation {
    static let moduleIdentifier = "studio.hypertext.apps.curfew.screensaver"
    static let settingsURL =
        URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!

    enum State: Equatable {
        case missingCompanion
        case available(version: String)
        case installRequestAccepted(version: String)
        case installed(version: String)
        case versionMismatch(bundled: String, installed: String)
        case operationRejected(reason: String)
    }

    struct Locations {
        let bundledSaver: URL?
        let userInstallationDirectory: URL
    }

    let locations: Locations
    let open: (URL) -> Bool
    let removeOwnedSaver: (URL) throws -> Void

    func inspect() -> State {
        do {
            guard let bundled = locations.bundledSaver,
                  FileManager.default.fileExists(atPath: bundled.path) else {
                return .missingCompanion
            }
            let version = try validatedVersion(at: bundled)
            let installed = installationURL
            guard FileManager.default.fileExists(atPath: installed.path) else {
                return .available(version: version)
            }
            let installedVersion = try validatedVersion(at: installed)
            return installedVersion == version
                ? .installed(version: version)
                : .versionMismatch(bundled: version, installed: installedVersion)
        } catch {
            return .operationRejected(reason: "The screensaver location or metadata is invalid.")
        }
    }

    func requestInstallation() -> State {
        guard let bundled = locations.bundledSaver,
              FileManager.default.fileExists(atPath: bundled.path) else { return .missingCompanion }
        do {
            let version = try validatedVersion(at: bundled)
            guard open(bundled) else {
                return .operationRejected(reason: "macOS could not open the screensaver installer.")
            }
            return .installRequestAccepted(version: version)
        } catch {
            return .operationRejected(
                reason: "The bundled screensaver location or metadata is invalid."
            )
        }
    }

    func openSystemSettings() -> State {
        guard open(Self.settingsURL) else {
            return .operationRejected(reason: "macOS could not open Screen Saver settings.")
        }
        return inspect()
    }

    func removeInstallation() -> State {
        do {
            _ = try validatedVersion(at: installationURL)
            try removeOwnedSaver(installationURL)
            return inspect()
        } catch {
            return .operationRejected(reason: "The owned screensaver could not be safely removed.")
        }
    }

    private var installationURL: URL {
        locations.userInstallationDirectory.appendingPathComponent("Curfew.saver")
    }

    private enum ValidationError: Error {
        case invalidMetadata
    }

    /// Reads the property list only; neither Bundle nor the saver executable is loaded.
    private func validatedVersion(at url: URL) throws -> String {
        guard url.isFileURL, url.lastPathComponent == "Curfew.saver",
              url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL
                  .path else {
            throw ValidationError.invalidMetadata
        }
        let contents = url.appendingPathComponent("Contents")
        for directory in [url, contents] {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw ValidationError.invalidMetadata
            }
        }
        let plist = contents.appendingPathComponent("Info.plist")
        guard plist.standardizedFileURL.path == plist.resolvingSymlinksInPath().standardizedFileURL
            .path,
            let data = try BoundedRegularFileReader.read(plist, maximumBytes: 65536),
            let metadata = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any],
            metadata["CFBundleIdentifier"] as? String == Self.moduleIdentifier,
            metadata["CFBundlePackageType"] as? String == "BNDL",
            let rawVersion = metadata["CFBundleShortVersionString"] as? String else {
            throw ValidationError.invalidMetadata
        }
        let version = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { throw ValidationError.invalidMetadata }
        return version
    }
}
