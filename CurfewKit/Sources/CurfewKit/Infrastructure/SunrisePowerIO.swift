import Foundation
import IOKit

/// Inert test-first contract. No operation invokes its injected function yet.
/// Calls must be serialized by the owner; live bindings are a later increment.
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
        case unimplemented
        case foreignEvent
        case foreignAssertion
        case invalidTimeout
        case native(operation: String, code: Int32)
    }

    public init(owner: String, functions: Functions) {}

    public func schedule(_ event: Event) throws {
        throw Failure.unimplemented
    }

    public func cancel(_ event: Event) throws {
        throw Failure.unimplemented
    }

    public func declareUserActivity() throws {
        throw Failure.unimplemented
    }

    public func acquireDisplayAssertion(
        until: Date, now: Date
    ) throws -> SunriseDisplayDelivery.AssertionToken {
        throw Failure.unimplemented
    }

    public func releaseDisplayAssertion(_ token: SunriseDisplayDelivery.AssertionToken) throws {
        throw Failure.unimplemented
    }

    public func cleanup() throws {
        throw Failure.unimplemented
    }

    public func onExternalPower() -> Bool {
        false
    }
}
