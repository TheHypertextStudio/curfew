import Foundation
import Security

/// Both peers pin the same signing team and the exact role identifier. The
/// team comes from their own signed executable, never a user preference.
public struct DaemonSigningIdentity: Equatable, Sendable {
    public let machServiceName: String
    public let clientRequirement: String
    public let serverRequirement: String

    public init?(flavor: CurfewFlavor, teamIdentifier: String?) {
        guard let teamIdentifier, teamIdentifier.utf8.count == 10,
              teamIdentifier.utf8
              .allSatisfy({ (65 ... 90).contains($0) || (48 ... 57).contains($0) })
        else { return nil }
        self.machServiceName = flavor.daemonLabel
        let anchor = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and identifier "
        self.clientRequirement = anchor + "\"\(flavor.bundleIdentifier)\""
        self.serverRequirement = anchor + "\"curfew-daemon\""
    }

    public static var current: Self? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        ) == errSecSuccess,
            let dictionary = info as? [String: Any]
        else { return nil }
        return Self(
            flavor: .current,
            teamIdentifier: dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        )
    }
}
