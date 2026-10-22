import Foundation

/// Local presentation persistence only. An adapter owns atomic replacement of each slot.
/// This deliberately inert scaffold exists solely to permit execution of failing contracts.
public final class RestCompanionPresentationStore {
    public enum Slot: Hashable, Sendable {
        case appearance
        case occurrence
        case readbackRequest
    }

    public struct Publication: Equatable, Sendable {
        public let generation: UUID
        public let presentation: RestCompanionExport
        public let readbackNonce: UUID?
    }

    public static let maximumAppearanceBytes = RestCompanionExport.maximumEnvelopeBytes + 4096
    public static let maximumOccurrenceBytes = 4096

    public init(
        read _: @escaping (Slot, Int) throws -> Data?,
        write _: @escaping (Slot, Data) throws -> Void,
        inspectImageHeader _: @escaping (Data) throws -> RestCompanionExport.ImageDimensions
    ) {}

    public func publish(snapshot _: RestSceneSnapshot, imageData _: Data?) throws {}

    public func read(at _: Date) -> Publication? {
        nil
    }

    public func acknowledgement(for _: Publication) throws -> Data {
        Data()
    }

    public func requestReadback() throws -> UUID {
        UUID()
    }

    public func matchesCurrentPublication(_: Data) -> Bool {
        false
    }
}
