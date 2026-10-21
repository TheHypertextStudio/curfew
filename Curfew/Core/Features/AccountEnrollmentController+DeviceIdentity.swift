import CurfewKit
import Foundation

@MainActor
extension AccountEnrollmentController {
    func loadOrCreateDeviceID() throws -> UUID {
        if let data = try secretStore.data(for: "account-device-id"),
           let text = String(data: data, encoding: .utf8),
           let identifier = UUID(uuidString: text) {
            return identifier
        }
        let identifier = UUID()
        try secretStore.save(
            Data(identifier.uuidString.lowercased().utf8),
            for: "account-device-id"
        )
        return identifier
    }
}
