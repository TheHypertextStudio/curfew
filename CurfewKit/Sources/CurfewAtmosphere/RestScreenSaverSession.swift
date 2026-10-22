import CoreGraphics
import CurfewKit
import Foundation

/// Host-driven presentation lifecycle. No timer or enforcement authority lives here.
@MainActor
public final class RestScreenSaverSession {
    public private(set) var snapshot: RestSceneSnapshot?
    public private(set) var image: CGImage?
    private let read: (Date) -> RestCompanionPresentationStore.Publication?
    private let acknowledge: (RestCompanionPresentationStore.Publication) throws -> Void
    private let decodeImage: (Data) -> CGImage?
    private var running = false
    private var generation: UUID?
    private var acknowledgedGeneration: UUID?
    private var acknowledgedNonce: UUID?

    public init(
        read: @escaping (Date) -> RestCompanionPresentationStore.Publication?,
        acknowledge: @escaping (RestCompanionPresentationStore.Publication) throws -> Void,
        decodeImage: @escaping (Data) -> CGImage?
    ) {
        self.read = read
        self.acknowledge = acknowledge
        self.decodeImage = decodeImage
    }

    public convenience init(
        preferences: RestScreenSaverPreferences,
        decodeImage: @escaping (Data) -> CGImage?
    ) {
        self.init(
            read: preferences.read(at:),
            acknowledge: preferences.acknowledge(_:),
            decodeImage: decodeImage
        )
    }

    public func start(at date: Date) {
        stop()
        running = true
        refresh(at: date)
    }

    public func frame(at date: Date, timeZone: TimeZone) -> RestSceneSnapshot.Frame? {
        guard running else { return nil }
        refresh(at: date)
        return snapshot?.resolve(at: date, timeZone: timeZone)
    }

    public func stop() {
        running = false
        snapshot = nil
        image = nil
        generation = nil
        acknowledgedGeneration = nil
        acknowledgedNonce = nil
    }

    private func refresh(at date: Date) {
        guard let publication = read(date) else {
            if let snapshot {
                self.snapshot = RestSceneSnapshot(
                    version: snapshot.version, expiresAt: Date(timeIntervalSince1970: 0),
                    appearance: snapshot.appearance, lockDate: nil, unlockDate: nil
                )
            }
            return
        }
        snapshot = RestSceneSnapshot(presentation: publication.presentation)
        if generation != publication.generation {
            image = publication.presentation.appearance.background == .image
                ? publication.presentation.imageData.flatMap(decodeImage) : nil
            generation = publication.generation
        }
        acknowledgeIfNeeded(publication)
    }

    private func acknowledgeIfNeeded(_ publication: RestCompanionPresentationStore.Publication) {
        guard let nonce = publication.readbackNonce,
              acknowledgedGeneration != publication.generation || acknowledgedNonce != nonce
        else { return }
        do {
            try acknowledge(publication)
            acknowledgedGeneration = publication.generation
            acknowledgedNonce = nonce
        } catch {
            // No receipt is claimed. A later host frame retries this same fresh request.
            acknowledgedGeneration = nil
            acknowledgedNonce = nil
        }
    }
}
