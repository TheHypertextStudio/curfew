import CurfewAtmosphere
import CurfewKit
import Foundation
import Observation

/// Explicit live composition. Ordinary test models never construct this graph.
@Observable
@MainActor
final class RestExperienceRuntime {
    let sunrise = SunriseModelRuntime()
    @ObservationIgnored var publisher: RestCompanionPublisher?
    @ObservationIgnored var readback: () -> Bool = { false }
    @ObservationIgnored var stopDisplay: () throws -> Void = {}
    var configured = false
    var companionReadbackVerified = false
}

@MainActor
extension CurfewAppModel {
    func handleRestAppearanceChange(from previous: RestAppearancePreferences) {
        guard restAppearance != previous else { return }
        restAppearanceStore.save(restAppearance)
        advanceRestExperience()
    }

    func configureRestExperience() {
        guard !isDemoSession, !RuntimeEnvironment.hasLoadedTestRuntime,
              !restRuntime.configured else { return }
        let owner = CurfewFlavor.current.daemonLabel + ".sunrise"
        // Separate ownership prevents activity cleanup from releasing the
        // delivery policy's retained token after a failed native release.
        let activity = SunrisePowerIO(owner: owner, functions: SunrisePowerIO.liveFunctions)
        let display = SunrisePowerIO(owner: owner, functions: SunrisePowerIO.liveFunctions)
        let delivery = SunriseDisplayDelivery(
            declareUserActivity: activity.declareUserActivity,
            acquireDisplayAssertion: { try display.acquireDisplayAssertion(until: $0, now: Date())
            },
            releaseDisplayAssertion: display.releaseDisplayAssertion
        )
        let rpc = XPCPrivilegedDaemonClient()
        sunriseWakeCoordinator = SunriseWakeCoordinator(
            operations: .init(
                replace: { plan in
                    do {
                        try await rpc.replaceSunriseWakePlan(plan)
                    } catch {
                        throw Self.sunriseHelperFailure(error)
                    }
                },
                cancel: {
                    do {
                        try await rpc.cancelSunriseWakePlan()
                    } catch {
                        throw Self.sunriseHelperFailure(error)
                    }
                }
            ),
            displayDelivery: delivery, cleanupNativeAssertions: activity.cleanup
        )
        sunriseOnExternalPower = display.onExternalPower
        sunriseCalendar = .autoupdatingCurrent
        restRuntime.stopDisplay = {
            // Attempt both owners even if one release fails.
            var failure: (any Error)?
            do { try delivery.stop() } catch { failure = error }
            do { try activity.cleanup() } catch { failure = failure ?? error }
            if let failure {
                throw failure
            }
        }
        configureCompanionPublisher()
        restRuntime.configured = true
        advanceRestExperience()
    }

    /// Uses the existing display clock; helper latency cannot block publication
    /// or synchronous display eligibility inside the wake coordinator.
    func advanceRestExperience() {
        guard restRuntime.configured, !isDemoSession else { return }
        let snapshot = restCompanionSnapshot
        if let publisher = restRuntime.publisher {
            Task { await publisher.reconcile(snapshot: snapshot, allowsPublication: true) }
        }
        restRuntime.companionReadbackVerified = restRuntime.readback()
        Task { await reconcileSunriseWake() }
    }

    func stopRestExperienceDisplay() {
        restRuntime.configured = false
        do {
            try restRuntime.stopDisplay()
        } catch {
            sunriseStatus = .requestRejected
            NSLog("Curfew Sunrise assertion cleanup failed: %@", error.localizedDescription)
        }
    }

    private func configureCompanionPublisher() {
        do {
            let preferences = try RestScreenSaverPreferences.system()
            let directory = restBackgroundDirectory
            restRuntime.publisher = RestCompanionPublisher(
                readOwnedImage: { filename in
                    await Task.detached(priority: .utility) {
                        RestBackgroundImageStore(directory: directory)
                            .encodedImage(named: filename)
                    }.value
                },
                publish: { snapshot, bytes in
                    try preferences.publish(snapshot: snapshot, imageData: bytes)
                    // Require a fresh host acknowledgement for this publication.
                    _ = try preferences.requestReadback()
                }
            )
            restRuntime.readback = preferences.hasAcknowledgedCurrentPublication
        } catch {
            NSLog("Curfew screensaver preferences unavailable: %@", error.localizedDescription)
        }
    }

    private static func sunriseHelperFailure(_ error: any Error) -> SunriseWakeCoordinator
        .HelperFailure {
        if let failure = error as? SunriseDaemonRPCError, failure == .unavailable {
            return .unavailable
        }
        return .rejected
    }
}
