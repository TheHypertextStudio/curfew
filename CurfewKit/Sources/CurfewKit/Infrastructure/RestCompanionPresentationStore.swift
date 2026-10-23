import Foundation

/// Local presentation persistence only. An adapter owns atomic replacement of each slot.
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

    private struct AppearanceRecord: Codable {
        let version: Int
        let generation: UUID
        let expiresAt: Date
        let appearance: RestCompanionExport.Appearance
        let imageData: Data?
    }

    private struct OccurrenceRecord: Codable {
        let version: Int
        let generation: UUID
        let expiresAt: Date
        let lockDate: Date?
        let unlockDate: Date?
    }

    private struct Readback: Codable {
        let version: Int
        let generation: UUID
        let nonce: UUID?
    }

    private enum StorageError: Error {
        case missingAppearance
        case oversizedRecord
    }

    // Appearance has no temporal authority. Its stable expiry never follows a clock tick.
    private static let neutralExpiry = Date(timeIntervalSinceReferenceDate: 0)
    private let readSlot: (Slot, Int) throws -> Data?
    private let writeSlot: (Slot, Data) throws -> Void
    private let inspectImageHeader: (Data) throws -> RestCompanionExport.ImageDimensions

    public init(
        read: @escaping (Slot, Int) throws -> Data?,
        write: @escaping (Slot, Data) throws -> Void,
        inspectImageHeader: @escaping (Data) throws -> RestCompanionExport.ImageDimensions
    ) {
        self.readSlot = read
        self.writeSlot = write
        self.inspectImageHeader = inspectImageHeader
    }

    public func publish(snapshot: RestSceneSnapshot, imageData: Data?) throws {
        let neutral = RestSceneSnapshot(
            version: snapshot.version, expiresAt: Self.neutralExpiry,
            appearance: snapshot.appearance, lockDate: nil, unlockDate: nil
        )
        let exportBytes = try RestCompanionExport.encode(
            snapshot: neutral, imageData: imageData, inspectImageHeader: inspectImageHeader
        )
        let presentation = try RestCompanionExport.decode(
            exportBytes, inspectImageHeader: inspectImageHeader
        )
        let previous = try loadAppearance()
        let generation: UUID
        if let previous, previous.0.appearance == presentation.appearance,
           previous.0.imageData == presentation.imageData {
            generation = previous.1
        } else {
            generation = UUID()
            let record = AppearanceRecord(
                version: RestCompanionExport.currentVersion, generation: generation,
                expiresAt: Self.neutralExpiry, appearance: presentation.appearance,
                imageData: presentation.imageData
            )
            try writeSlot(.appearance, encode(record, maximum: Self.maximumAppearanceBytes))
        }
        let occurrence = OccurrenceRecord(
            version: RestCompanionExport.currentVersion, generation: generation,
            expiresAt: snapshot.expiresAt, lockDate: snapshot.lockDate,
            unlockDate: snapshot.unlockDate
        )
        let bytes = try encode(occurrence, maximum: Self.maximumOccurrenceBytes)
        if try boundedRead(.occurrence, maximum: Self.maximumOccurrenceBytes) != bytes {
            try writeSlot(.occurrence, bytes)
        }
    }

    public func read(at now: Date) -> Publication? {
        guard let stored = try? loadAppearance() else { return nil }
        let base = stored.0
        let generation = stored.1
        var expiry = Self.neutralExpiry
        var lockDate: Date?
        var unlockDate: Date?
        if let occurrence: OccurrenceRecord = loadSmall(.occurrence),
           occurrence.version == RestCompanionExport.currentVersion,
           occurrence.generation == generation,
           now.timeIntervalSinceReferenceDate.isFinite,
           occurrence.expiresAt.timeIntervalSinceReferenceDate.isFinite,
           now < occurrence.expiresAt,
           let lock = occurrence.lockDate, let unlock = occurrence.unlockDate,
           lock.timeIntervalSinceReferenceDate.isFinite,
           unlock.timeIntervalSinceReferenceDate.isFinite, lock < unlock {
            expiry = occurrence.expiresAt
            lockDate = lock
            unlockDate = unlock
        }
        let request: Readback? = loadSmall(.readbackRequest)
        let nonce = request?.version == RestCompanionExport.currentVersion
            && request?.generation == generation ? request?.nonce : nil
        return Publication(
            generation: generation,
            presentation: RestCompanionExport(
                version: base.version, expiresAt: expiry, appearance: base.appearance,
                lockDate: lockDate, unlockDate: unlockDate, imageData: base.imageData
            ),
            readbackNonce: nonce
        )
    }

    /// A Publication can only originate from this store's validated read path.
    /// Cache its already consent-filtered appearance without exporting it again.
    public func cacheAppearance(from publication: Publication) throws {
        let record = AppearanceRecord(
            version: RestCompanionExport.currentVersion, generation: publication.generation,
            expiresAt: Self.neutralExpiry, appearance: publication.presentation.appearance,
            imageData: publication.presentation.imageData
        )
        let bytes = try encode(record, maximum: Self.maximumAppearanceBytes)
        if try boundedRead(.appearance, maximum: Self.maximumAppearanceBytes) != bytes {
            try writeSlot(.appearance, bytes)
        }
    }

    public func acknowledgement(for publication: Publication) throws -> Data {
        try encode(Readback(
            version: RestCompanionExport.currentVersion,
            generation: publication.generation, nonce: publication.readbackNonce
        ), maximum: Self.maximumOccurrenceBytes)
    }

    public func requestReadback() throws -> UUID {
        guard let appearance = try loadAppearance() else { throw StorageError.missingAppearance }
        let nonce = UUID()
        try writeSlot(.readbackRequest, encode(Readback(
            version: RestCompanionExport.currentVersion, generation: appearance.1, nonce: nonce
        ), maximum: Self.maximumOccurrenceBytes))
        return nonce
    }

    public func matchesCurrentPublication(_ bytes: Data) -> Bool {
        guard bytes.count <= Self.maximumOccurrenceBytes,
              let acknowledgement = try? JSONDecoder().decode(Readback.self, from: bytes),
              acknowledgement.version == RestCompanionExport.currentVersion,
              let nonce = acknowledgement.nonce,
              let request: Readback = loadSmall(.readbackRequest),
              request.version == acknowledgement.version,
              request.generation == acknowledgement.generation, request.nonce == nonce,
              let appearance = try? loadAppearance()
        else { return false }
        return appearance.1 == acknowledgement.generation
    }

    private func loadAppearance() throws -> (RestCompanionExport, UUID)? {
        guard let bytes = try boundedRead(.appearance, maximum: Self.maximumAppearanceBytes) else {
            return nil
        }
        // The export decoder ignores bookkeeping but independently enforces its own bounds
        // and visual allowlist before any consumer can access an image.
        guard let record = try? JSONDecoder().decode(AppearanceRecord.self, from: bytes),
              record.expiresAt == Self.neutralExpiry,
              let presentation = try? RestCompanionExport.decode(
                  bytes, inspectImageHeader: inspectImageHeader
              )
        else { return nil }
        return (presentation, record.generation)
    }

    private func loadSmall<Value: Decodable>(_ slot: Slot) -> Value? {
        guard let bytes = try? boundedRead(slot, maximum: Self.maximumOccurrenceBytes) else {
            return nil
        }
        return try? JSONDecoder().decode(Value.self, from: bytes)
    }

    private func boundedRead(_ slot: Slot, maximum: Int) throws -> Data? {
        guard let bytes = try readSlot(slot, maximum), bytes.count <= maximum else { return nil }
        return bytes
    }

    private func encode(_ value: some Encodable, maximum: Int) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(value)
        guard bytes.count <= maximum else { throw StorageError.oversizedRecord }
        return bytes
    }
}
