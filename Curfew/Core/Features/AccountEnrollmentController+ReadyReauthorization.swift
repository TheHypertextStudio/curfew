import CurfewKit
import Foundation

@MainActor
extension AccountEnrollmentController {
    @discardableResult
    func reconnectEnrolledMac(_ enrollment: AccountDeviceEnrollment) async -> Bool {
        switch state {
        case .accountFree:
            break
        case .ready(let saved) where saved == enrollment:
            break
        default:
            return false
        }
        let owner: RemoteCommandEnrollment
        do {
            guard let saved = try remoteCommandEnrollmentStore.load(),
                  saved.deviceID == enrollment.deviceID,
                  !saved.userID.isEmpty
            else {
                enrollmentRetryError = AccountEnrollmentFailureCopy.unanchoredCheckpoint
                return false
            }
            owner = saved
        } catch {
            enrollmentRetryError = AccountEnrollmentFailureCopy.unanchoredCheckpoint
            return false
        }
        signInCancellationRequested = false
        state = .signingIn
        browserSignInURL = nil
        do {
            _ = try await authenticate(expectedAccountUserID: owner.userID)
            do {
                try AccountEnrollmentPendingStore(secretStore: secretStore).markReady(enrollment)
            } catch {
                state = .storageUnavailable
                return false
            }
            enrollmentRetryError = nil
            state = .ready(enrollment)
            return true
        } catch AccountOAuthEnrollmentError.accountMismatch {
            enrollmentRetryError = AccountEnrollmentFailureCopy.wrongAccount
        } catch OAuthCredentialPersistenceError.storageUnavailable {
            state = .storageUnavailable
            return false
        } catch is CancellationError {
            // The existing device and its credentials are untouched.
        } catch {
            enrollmentRetryError = AccountEnrollmentFailureCopy.reauthorizationMessage(for: error)
        }
        state = .ready(enrollment)
        return false
    }
}
