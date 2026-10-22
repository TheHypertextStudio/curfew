import Foundation
import IOKit

/// Validates ownership and bounds before invoking injected power functions.
/// Calls must be serialized by the owner.
public final class SunrisePowerIO {
    public static let notFound: Int32 = kIOReturnNotFound

    public struct Event: Equatable {
        public let owner: String
        public let date: Date
        public let type: String

        public init(owner: String, date: Date, type: String) {
            self.owner = owner
            self.date = date
            self.type = type
        }
    }

    public struct DisplayRequest: Equatable {
        public let type: String
        public let timeout: TimeInterval
        public let timeoutAction: String

        public init(type: String, timeout: TimeInterval, timeoutAction: String) {
            self.type = type
            self.timeout = timeout
            self.timeoutAction = timeoutAction
        }
    }

    public struct Functions {
        public let schedule: (Event) -> Int32
        public let cancel: (Event) -> Int32
        public let copyScheduled: () -> (Int32, [Event])
        public let declareActivity: () -> (Int32, UInt32)
        public let createDisplay: (DisplayRequest) -> (Int32, UInt32)
        public let release: (UInt32) -> Int32
        public let powerSource: () -> String?

        public init(
            schedule: @escaping (Event) -> Int32,
            cancel: @escaping (Event) -> Int32,
            copyScheduled: @escaping () -> (Int32, [Event]),
            declareActivity: @escaping () -> (Int32, UInt32),
            createDisplay: @escaping (DisplayRequest) -> (Int32, UInt32),
            release: @escaping (UInt32) -> Int32,
            powerSource: @escaping () -> String?
        ) {
            self.schedule = schedule
            self.cancel = cancel
            self.copyScheduled = copyScheduled
            self.declareActivity = declareActivity
            self.createDisplay = createDisplay
            self.release = release
            self.powerSource = powerSource
        }
    }

    public enum Failure: Error, Equatable {
        case foreignEvent
        case foreignAssertion
        case invalidTimeout
        case native(operation: String, code: Int32)
    }

    private let owner: String
    private let functions: Functions
    private var ownedAssertions: Set<UInt32> = []

    public init(owner: String, functions: Functions) {
        self.owner = owner
        self.functions = functions
    }

    public func schedule(_ event: Event) throws {
        try validate(event)
        try check(functions.schedule(event), operation: "schedule")
    }

    public func cancel(_ event: Event) throws {
        try validate(event)
        let (status, events) = functions.copyScheduled()
        try check(status, operation: "copyScheduled")
        guard events.contains(event) else { return }
        let result = functions.cancel(event)
        guard result != Self.notFound else { return }
        try check(result, operation: "cancel")
    }

    public func declareUserActivity() throws {
        let (status, assertionID) = functions.declareActivity()
        try check(status, operation: "declareActivity")
        ownedAssertions.insert(assertionID)
        try releaseOwned(assertionID)
    }

    public func acquireDisplayAssertion(
        until: Date, now: Date
    ) throws -> SunriseDisplayDelivery.AssertionToken {
        let timeout = until.timeIntervalSince(now)
        guard now.timeIntervalSinceReferenceDate.isFinite,
              until.timeIntervalSinceReferenceDate.isFinite,
              timeout.isFinite, timeout > 0, timeout <= 3900
        else { throw Failure.invalidTimeout }
        let (status, assertionID) = functions.createDisplay(.init(
            type: "NoDisplaySleepAssertion", timeout: timeout,
            timeoutAction: "TimeoutActionRelease"
        ))
        try check(status, operation: "createDisplay")
        ownedAssertions.insert(assertionID)
        return .init(rawValue: assertionID)
    }

    public func releaseDisplayAssertion(_ token: SunriseDisplayDelivery.AssertionToken) throws {
        guard ownedAssertions.contains(token.rawValue) else { throw Failure.foreignAssertion }
        try releaseOwned(token.rawValue)
    }

    public func cleanup() throws {
        var firstFailure: (any Error)?
        for assertionID in ownedAssertions.sorted() {
            do {
                try releaseOwned(assertionID)
            } catch {
                if firstFailure == nil {
                    firstFailure = error
                }
            }
        }
        if let firstFailure {
            throw firstFailure
        }
    }

    public func onExternalPower() -> Bool {
        functions.powerSource() == "AC Power"
    }

    private func validate(_ event: Event) throws {
        guard event.owner == owner, event.type == "wake",
              event.date.timeIntervalSinceReferenceDate.isFinite
        else { throw Failure.foreignEvent }
    }

    private func check(_ status: Int32, operation: String) throws {
        guard status == 0 else { throw Failure.native(operation: operation, code: status) }
    }

    private func releaseOwned(_ assertionID: UInt32) throws {
        let status = functions.release(assertionID)
        if status != Self.notFound {
            try check(status, operation: "release")
        }
        ownedAssertions.remove(assertionID)
    }
}
