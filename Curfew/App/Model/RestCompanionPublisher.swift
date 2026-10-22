import CurfewKit
import Foundation

/// App-owned publication sequencing. A written publication is not saver-process readback.
/// All effects are injected; activation and runtime disarming belong to app composition.
@MainActor
final class RestCompanionPublisher {
    enum Status: Equatable {
        case notPublished
        case publicationWritten
        case failed
    }

    private let readOwnedImage: (String) async throws -> Data?
    private let publish: (RestSceneSnapshot, Data?) throws -> Void
    private(set) var status: Status = .notPublished

    init(
        readOwnedImage: @escaping (String) async throws -> Data?,
        publish: @escaping (RestSceneSnapshot, Data?) throws -> Void
    ) {
        self.readOwnedImage = readOwnedImage
        self.publish = publish
    }

    /// Inert until actual native contracts observe the missing publication behavior.
    func reconcile(snapshot _: RestSceneSnapshot, allowsPublication _: Bool = false) async {}
}
