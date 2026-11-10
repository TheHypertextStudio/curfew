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
    private var revision: UInt64 = 0
    private var requestedSnapshot: RestSceneSnapshot?
    private var writtenSnapshot: RestSceneSnapshot?
    private var cachedFilename: String?
    private var cachedBytes: Data?

    init(
        readOwnedImage: @escaping (String) async throws -> Data?,
        publish: @escaping (RestSceneSnapshot, Data?) throws -> Void
    ) {
        self.readOwnedImage = readOwnedImage
        self.publish = publish
    }

    func reconcile(snapshot: RestSceneSnapshot, allowsPublication: Bool = false) async {
        guard allowsPublication else {
            revision &+= 1
            requestedSnapshot = nil
            writtenSnapshot = nil
            cachedFilename = nil
            cachedBytes = nil
            status = .notPublished
            return
        }
        if snapshot == writtenSnapshot {
            // Returning to an already written choice still invalidates a newer
            // suspended read; that obsolete choice must not publish afterward.
            revision &+= 1
            requestedSnapshot = nil
            status = .publicationWritten
            return
        }
        guard snapshot != requestedSnapshot else { return }
        revision &+= 1
        let operation = revision
        requestedSnapshot = snapshot
        do {
            var bytes: Data?
            if snapshot.appearance.background == .image,
               let filename = snapshot.appearance.ownedImageFilename {
                if filename == cachedFilename {
                    bytes = cachedBytes
                } else {
                    bytes = try await readOwnedImage(filename)
                    guard operation == revision else { return }
                    cachedFilename = filename
                    cachedBytes = bytes
                }
            }
            guard operation == revision else { return }
            try publish(snapshot, bytes)
            writtenSnapshot = snapshot
            requestedSnapshot = nil
            status = .publicationWritten
        } catch {
            guard operation == revision else { return }
            requestedSnapshot = nil
            status = .failed
        }
    }
}
