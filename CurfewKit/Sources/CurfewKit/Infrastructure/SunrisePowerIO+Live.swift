import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

public extension SunrisePowerIO {
    /// Native calls occur only when a later owner invokes these injected closures.
    /// The adapter must validate its fixed event owner before invoking them.
    static var liveFunctions: Functions {
        Functions(
            schedule: { event in
                guard event.type == kIOPMAutoWake,
                      event.date.timeIntervalSinceReferenceDate.isFinite
                else { return kIOReturnBadArgument }
                return IOPMSchedulePowerEvent(
                    event.date as CFDate, event.owner as CFString, kIOPMAutoWake as CFString
                )
            },
            cancel: { event in
                guard event.type == kIOPMAutoWake,
                      event.date.timeIntervalSinceReferenceDate.isFinite
                else { return kIOReturnBadArgument }
                return IOPMCancelScheduledPowerEvent(
                    event.date as CFDate, event.owner as CFString, kIOPMAutoWake as CFString
                )
            },
            copyScheduled: {
                // The SDK explicitly documents NULL when no events are scheduled.
                guard let copied = IOPMCopyScheduledPowerEvents() else {
                    return (kIOReturnSuccess, [])
                }
                let entries = copied.takeRetainedValue() as NSArray
                var events: [Event] = []
                for entry in entries {
                    guard let dictionary = entry as? NSDictionary,
                          let owner = dictionary[kIOPMPowerEventAppNameKey] as? String,
                          let date = dictionary[kIOPMPowerEventTimeKey] as? Date,
                          date.timeIntervalSinceReferenceDate.isFinite,
                          let type = dictionary[kIOPMPowerEventTypeKey] as? String
                    else {
                        // Do not silently drop malformed identities or return partial data.
                        return (kIOReturnBadArgument, [])
                    }
                    events.append(Event(owner: owner, date: date, type: type))
                }
                return (kIOReturnSuccess, events)
            },
            declareActivity: {
                var assertionID: IOPMAssertionID = 0
                let status = IOPMAssertionDeclareUserActivity(
                    "Curfew Sunrise user activity" as CFString,
                    kIOPMUserActiveLocal,
                    &assertionID
                )
                return (status, assertionID)
            },
            createDisplay: { request in
                guard request.type == (kIOPMAssertionTypeNoDisplaySleep as String),
                      request.timeoutAction == (kIOPMAssertionTimeoutActionRelease as String),
                      request.timeout.isFinite,
                      request.timeout > 0,
                      request.timeout <= 3900
                else { return (kIOReturnBadArgument, 0) }
                var assertionID: IOPMAssertionID = 0
                let status = IOPMAssertionCreateWithDescription(
                    kIOPMAssertionTypeNoDisplaySleep as CFString,
                    "Curfew Sunrise display" as CFString,
                    nil, nil, nil,
                    request.timeout,
                    kIOPMAssertionTimeoutActionRelease as CFString,
                    &assertionID
                )
                return (status, assertionID)
            },
            release: { assertionID in
                IOPMAssertionRelease(assertionID)
            },
            powerSource: {
                guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                      let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue(),
                      (source as String) == kIOPSACPowerValue
                else { return nil }
                return kIOPSACPowerValue
            }
        )
    }
}
