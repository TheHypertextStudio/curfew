import Foundation
import Security

/// One short-lived authorization context for the reads in a single repair.
/// Rights name exact files and permit reads only. Nothing is persisted.
final nonisolated class HelperReadAuthorization: @unchecked Sendable {
    private var authorization: AuthorizationRef?

    deinit {
        if let authorization {
            AuthorizationFree(authorization, [])
        }
    }

    func externalForm(for path: String) throws -> Data {
        if authorization == nil {
            guard AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess
            else {
                throw HelperMaintenanceError.commandFailed
            }
        }
        guard let authorization else { throw HelperMaintenanceError.commandFailed }
        let message = "Curfew needs to read its saved protection state "
            + "before repairing background protection."
        let result = ("sys.openfile.readonly." + path).withCString { rightName in
            message.withCString { prompt in
                var right = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
                var environment = AuthorizationItem(
                    name: kAuthorizationEnvironmentPrompt,
                    valueLength: strlen(prompt), value: UnsafeMutableRawPointer(mutating: prompt),
                    flags: 0
                )
                return withUnsafeMutablePointer(to: &right) { rightsPointer in
                    withUnsafeMutablePointer(to: &environment) { environmentPointer in
                        var rights = AuthorizationRights(count: 1, items: rightsPointer)
                        var environments = AuthorizationEnvironment(
                            count: 1,
                            items: environmentPointer
                        )
                        return AuthorizationCopyRights(
                            authorization, &rights, &environments,
                            [.interactionAllowed, .extendRights], nil
                        )
                    }
                }
            }
        }
        guard result == errAuthorizationSuccess else { throw HelperMaintenanceError.commandFailed }
        var external = AuthorizationExternalForm()
        guard AuthorizationMakeExternalForm(authorization, &external) == errAuthorizationSuccess
        else {
            throw HelperMaintenanceError.commandFailed
        }
        return withUnsafeBytes(of: &external) { Data($0) }
    }
}
