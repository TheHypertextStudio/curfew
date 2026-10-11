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
    static let accessDenied = "Curfew Account access was rejected."
}
