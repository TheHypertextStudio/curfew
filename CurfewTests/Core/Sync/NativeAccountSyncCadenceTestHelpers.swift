@testable import Curfew
import CurfewKit
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncOverrideCadenceTests {
    func makeTransport(
        secrets: NativeTransportMemorySecretStore,
        session: URLSession,
        pollingInterval: Duration = .seconds(15)
    ) -> NativeAccountSyncTransport {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-cadence-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return NativeAccountSyncTransport(
            secretStore: secrets,
            session: session,
            inboxStore: RemoteCommandInboxStore(directoryURL: root.appendingPathComponent("inbox")),
            resultExchangeStore: RemoteCommandResultExchangeStore(
                resultsURL: root.appendingPathComponent("results.json"),
                acknowledgementsDirectoryURL: root.appendingPathComponent("acknowledgements")
            ),
            enrollmentStore: RemoteCommandEnrollmentStore(
                recordURL: root.appendingPathComponent("enrollment.json")
            ),
            pollingInterval: pollingInterval,
            socketEnabled: false
        )
    }
}
