import Foundation

@MainActor
extension AccountEnrollmentController {
    func reconnectEnrolledMac(_ enrollment: AccountDeviceEnrollment) async {
        switch state {
        case .accountFree:
            break
        case .ready(let saved) where saved == enrollment:
            break
        default:
            return
        }
        let owner: RemoteCommandEnrollment
        do {
            guard let saved = try remoteCommandEnrollmentStore.load(),
                  saved.deviceID == enrollment.deviceID,
                  !saved.userID.isEmpty
            else {
                enrollmentRetryError = AccountEnrollmentFailureCopy.unanchoredCheckpoint
                return
            }
            owner = saved
        } catch {
            enrollmentRetryError = AccountEnrollmentFailureCopy.unanchoredCheckpoint
            return
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
                return
            }
            enrollmentRetryError = nil
        } catch AccountOAuthEnrollmentError.accountMismatch {
            enrollmentRetryError = AccountEnrollmentFailureCopy.wrongAccount
        } catch OAuthCredentialPersistenceError.storageUnavailable {
            state = .storageUnavailable
            return
        } catch is CancellationError {
            // The existing device and its credentials are untouched.
        } catch {
            enrollmentRetryError = AccountEnrollmentFailureCopy.reauthorization
        }
        state = .ready(enrollment)
    }
}
