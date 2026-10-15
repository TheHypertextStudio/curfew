import Foundation

enum AccountSyncStatus: Equatable {
    case accountFree
    case connecting
    case synchronized(Date)
    case pendingEncryption
    case offline
    case rejected(String)

    var requiresSameAccountSignIn: Bool {
        if case .rejected(AccountSyncRejectionReason.signInRequired) = self {
            return true
        }
        return false
    }
}

enum AccountSyncRejectionReason {
    static let signInRequired = "Curfew needs you to sign in again."
    static let localDeviceIdentityMissing = "Curfew cannot find this Mac’s local device identity."
    static let localDeviceIdentityInvalid = "Curfew cannot read this Mac’s saved device identity."
    static let accessDenied = "Curfew Account access was rejected."
}
