import Foundation

struct LocalScheduleJournal {
    private struct Record: Codable, Equatable {
        var schedule: WeeklySchedule
        var pending: PendingScheduleChange?
        var receipts: [MCPGrantReceipt] = []
        var legacyIDs: Set<UUID> = []

        init(_ settings: CurfewSettings) {
            self.schedule = settings.schedule
            self.pending = settings.pendingScheduleChange
        }

        func matches(_ settings: CurfewSettings) -> Bool {
            schedule == settings.schedule && pending == settings.pendingScheduleChange
        }
    }

    let recordURL: URL?
    private var memory: Record?
    private static let maximumBytes = 16 * 1024 * 1024

    init(recordURL: URL?) {
        self.recordURL = recordURL
    }

    mutating func prepare(settings: CurfewSettings, queue: MCPRequestQueueStore) throws {
        guard recordURL != nil else { return }
        try update { current in
            guard current == nil else { return }
            var initial = Record(settings)
            initial.legacyIDs = try Set(queue.load().filter {
                $0.tool == .setSchedule && $0.status == .pending
            }.map(\.id))
            current = initial
        }
    }

    func overlay(on settings: CurfewSettings) throws -> CurfewSettings {
        guard recordURL != nil, let record = try read() else { return settings }
        var result = settings
        result.schedule = record.schedule
        result.pendingScheduleChange = record.pending
        return result
    }

    mutating func commit(
        _ settings: CurfewSettings,
        replacing previous: CurfewSettings,
        request: MCPPendingRequest?,
        at date: Date
    ) throws {
        let requiresDurableState = recordURL != nil
        try update { current in
            guard current != nil || !requiresDurableState else { throw CocoaError(.fileNoSuchFile) }
            var record = current ?? Record(previous)
            if let request {
                guard request.tool == .setSchedule,
                      !record.legacyIDs.contains(request.id),
                      !record.receipts.contains(where: { $0.requestID == request.id }) else {
                    throw MCPRequestQueueError.conflictingIdentity
                }
                record.receipts.append(MCPGrantReceipt(request: request, appliedAt: date))
            }
            guard record.matches(previous) || !requiresDurableState else {
                throw CocoaError(.fileWriteUnknown)
            }
            record.schedule = settings.schedule
            record.pending = settings.pendingScheduleChange
            current = record
        }
    }

    func outcome(for request: MCPPendingRequest, now: Date) throws -> MCPPendingRequest? {
        guard request.tool == .setSchedule, let record = try read() else { return nil }
        var outcome = request
        if record.legacyIDs.contains(request.id) {
            outcome.status = .denied
            outcome.resolvedAt = now
            outcome.denialReason = "This request predates reliable schedule tracking. " +
                "Check your schedule before submitting a new request."
            return outcome
        }
        guard let receipt = record.receipts.first(where: { $0.requestID == request.id }) else {
            return nil
        }
        guard receipt.matches(request) else { throw MCPRequestQueueError.conflictingIdentity }
        outcome.status = .approved
        outcome.resolvedAt = receipt.appliedAt
        outcome.denialReason = nil
        return outcome
    }

    func protectedIDs() throws -> Set<UUID> {
        guard let record = try read() else { return [] }
        return record.legacyIDs.union(record.receipts.map(\.requestID))
    }

    mutating func acknowledge(_ outcome: MCPPendingRequest) throws {
        guard outcome.tool == .setSchedule else { return }
        try update { record in
            if outcome.status == .approved {
                record?.receipts.removeAll { $0.matches(outcome) }
            } else if outcome.status == .denied {
                record?.legacyIDs.remove(outcome.id)
            }
        }
    }

    private mutating func update(_ body: (inout Record?) throws -> Void) throws {
        guard let recordURL else {
            try body(&memory)
            return
        }
        try MCPRequestQueue.withExclusiveLock(at: recordURL) {
            let prior = try read()
            var next = prior
            try body(&next)
            guard let next, next != prior else { return }
            let data = try JSONEncoder().encode(next)
            guard data.count <= Self.maximumBytes
            else { throw BoundedRegularFileReadError.tooLarge }
            try BreakGlassPrivateFileWriter.write(data, to: recordURL, replaceExisting: true)
        }
    }

    private func read() throws -> Record? {
        guard let recordURL else { return memory }
        guard let data = try BoundedRegularFileReader.read(
            recordURL,
            maximumBytes: Self.maximumBytes
        )
        else { return nil }
        let record = try JSONDecoder().decode(Record.self, from: data)
        let ids = Set(record.receipts.map(\.requestID))
        guard ids.count == record.receipts.count,
              ids.isDisjoint(with: record.legacyIDs),
              record.receipts.allSatisfy({ $0.isValid(for: .setSchedule) }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return record
    }
}
