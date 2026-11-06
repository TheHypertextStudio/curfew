import CurfewKit
import Darwin
import Foundation
import Testing

struct ProtectedWorkConcurrencyTests {
    @Test("Every protected-work mutation waits for the record's shared lock")
    func mutationsWaitForLock() throws {
        for mutation in WorkMutation.allCases {
            try withConcurrentWorkStore { store in
                let existing = try store.claim(
                    label: "existing",
                    source: .cli,
                    now: Date(),
                    policy: .default
                )
                let lockURL = store.recordURL.appendingPathExtension("lock")
                let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
                #expect(descriptor >= 0)
                guard descriptor >= 0 else { return }
                defer { close(descriptor) }
                #expect(flock(descriptor, LOCK_EX) == 0)
                defer { flock(descriptor, LOCK_UN) }

                let started = DispatchSemaphore(value: 0)
                let finished = DispatchSemaphore(value: 0)
                let errors = WorkThreadErrors()
                let recordURL = store.recordURL
                DispatchQueue.global().async {
                    started.signal()
                    do {
                        try mutation.apply(
                            store: ProtectedWorkStore(recordURL: recordURL),
                            id: existing.id
                        )
                    } catch {
                        errors.append(error)
                    }
                    finished.signal()
                }
                #expect(started.wait(timeout: .now() + 2) == .success)
                let early = finished.wait(timeout: .now() + 0.15)
                #expect(early == .timedOut, "\(mutation.rawValue) must not bypass a held lock")
                #expect(flock(descriptor, LOCK_UN) == 0)
                if early == .timedOut {
                    #expect(finished.wait(timeout: .now() + 5) == .success)
                }
                #expect(errors.isEmpty)
            }
        }
    }

    @Test("Two concurrent wrappers retain every claim")
    func concurrentClaims() throws {
        try withConcurrentWorkStore { store in
            let gate = DispatchSemaphore(value: 0)
            let group = DispatchGroup()
            let errors = WorkThreadErrors()
            let recordURL = store.recordURL
            let queue = DispatchQueue(label: "protected-work-test", attributes: .concurrent)
            for worker in 0 ..< 2 {
                group.enter()
                queue.async {
                    gate.wait()
                    defer { group.leave() }
                    do {
                        let local = ProtectedWorkStore(recordURL: recordURL)
                        for index in 0 ..< 16 {
                            try local.claim(
                                label: "worker \(worker) job \(index)",
                                source: .cli,
                                now: Date(),
                                policy: .default
                            )
                        }
                    } catch {
                        errors.append(error)
                    }
                }
            }
            gate.signal()
            gate.signal()
            #expect(group.wait(timeout: .now() + 10) == .success)
            #expect(errors.isEmpty)
            #expect(store.load().count == 32)
        }
    }

    @Test("Unsafe lock symlinks fail without changing protected-work state")
    func unsafeLockEntry() throws {
        for mutation in WorkMutation.allCases {
            try withConcurrentWorkStore { store in
                let existing = try store.claim(
                    label: "existing",
                    source: .cli,
                    now: Date(),
                    policy: .default
                )
                let original = try Data(contentsOf: store.recordURL)
                let lockURL = store.recordURL.appendingPathExtension("lock")
                try? FileManager.default.removeItem(at: lockURL)
                try FileManager.default.createSymbolicLink(
                    at: lockURL,
                    withDestinationURL: store.recordURL
                )
                #expect(throws: (any Error).self) {
                    try mutation.apply(store: store, id: existing.id)
                }
                #expect(try Data(contentsOf: store.recordURL) == original)
            }
        }
    }
}

private enum WorkMutation: String, CaseIterable, Sendable {
    case claim, release, clear

    func apply(store: ProtectedWorkStore, id: UUID) throws {
        switch self {
        case .claim:
            try store.claim(label: "new claim", source: .cli, now: Date(), policy: .default)
        case .release:
            try store.release(id: id)
        case .clear:
            try store.clear()
        }
    }
}

private final class WorkThreadErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [any Error] = []

    var isEmpty: Bool {
        lock.withLock { errors.isEmpty }
    }

    func append(_ error: any Error) {
        lock.withLock { errors.append(error) }
    }
}

private func withConcurrentWorkStore(_ body: (ProtectedWorkStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(ProtectedWorkStore(recordURL: directory.appendingPathComponent("claims.json")))
}
