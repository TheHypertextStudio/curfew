import CoreGraphics
import CurfewKit
import Foundation

/// Host-driven presentation lifecycle. No timer or enforcement authority lives here.
@MainActor
public final class RestScreenSaverSession {
    public private(set) var snapshot: RestSceneSnapshot?
    public private(set) var image: CGImage?

    public init(
        read: @escaping (Date) -> RestCompanionPresentationStore.Publication?,
        acknowledge: @escaping (RestCompanionPresentationStore.Publication) throws -> Void,
        decodeImage: @escaping (Data) -> CGImage?
    ) {}

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

    public func start(at date: Date) {}

    public func frame(at date: Date, timeZone: TimeZone) -> RestSceneSnapshot.Frame? {
        nil
    }

    public func stop() {}
}
