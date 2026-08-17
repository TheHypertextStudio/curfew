import CurfewProtocols
import Foundation

enum AccountPeerRootKeyDistributor {
    static func envelopes(
        rootKey: Data,
        currentDeviceID: UUID,
        devices: [CurfewProtocols.AccountDeviceEnrollment],
        createdAt: Date
    ) throws -> [RootKeyEnvelope] {
        try devices
            .filter { $0.deviceID != currentDeviceID.uuidString.lowercased() }
            .map { peer in
                try AccountRootKeyEnvelopeCrypto.seal(
                    rootKey: rootKey,
                    recipient: peer,
                    createdAt: createdAt
                )
            }
    }
}
