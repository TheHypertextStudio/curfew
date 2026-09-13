import Foundation

@MainActor
extension NativeAccountSyncTransport {
    func isCurrentConnection(_ generation: Int) -> Bool {
        generation == connectionGeneration && !Task.isCancelled
    }

    func recordSuccessfulOperation(_ channel: AccountHealthChannel) {
        healthyChannels.insert(channel)
        guard healthyChannels.isSuperset(of: requiredChannels) else { return }
        onSynchronized?(now())
    }

    func recordPollFailure(_ error: Error, channel: AccountHealthChannel) {
        recordOperationFailure(error, channel: channel)
    }

    func recordOperationFailure(_ error: Error, channel: AccountHealthChannel) {
        healthyChannels.remove(channel)
        reportFailure(error)
    }

    private func reportFailure(_ error: Error) {
        if case NativeAccountSyncError.missingCredentials = error {
            onFailure?("Curfew needs you to sign in again.")
        } else if case AccountOAuthTokenRefreshError.missingCredentials = error {
            onFailure?("Curfew needs you to sign in again.")
        } else if case AccountOAuthTokenRefreshError.rejected = error {
            onFailure?("Curfew needs you to sign in again.")
        } else if case NativeAccountSyncError.rejected(let status) = error,
                  status == 401 || status == 403 {
            onFailure?("Curfew Account access was rejected.")
        } else {
            onOffline?()
        }
    }
}
