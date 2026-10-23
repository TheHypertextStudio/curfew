@testable import CurfewKit
import Testing

struct SupervisorRegistrationPolicyTests {
    @Test func ordinaryDebugCannotRegisterEvenOnStagingEndpoints() {
        #expect(!SupervisorRegistrationPolicy.allowsRegistration(
            debugBuild: true, explicitStagingOptIn: false, testHost: false, demo: false
        ))
    }

    @Test func productionAndExplicitStagingMayRegister() {
        #expect(SupervisorRegistrationPolicy.allowsRegistration(
            debugBuild: false, explicitStagingOptIn: false, testHost: false, demo: false
        ))
        #expect(SupervisorRegistrationPolicy.allowsRegistration(
            debugBuild: true, explicitStagingOptIn: true, testHost: false, demo: false
        ))
    }

    @Test func hostsAndCaptureLaunchesCannotRegister() {
        #expect(!SupervisorRegistrationPolicy.allowsRegistration(
            debugBuild: true, explicitStagingOptIn: true, testHost: true, demo: false
        ))
        #expect(!SupervisorRegistrationPolicy.allowsRegistration(
            debugBuild: false, explicitStagingOptIn: false, testHost: true, demo: false
        ))
        #expect(!SupervisorRegistrationPolicy.allowsRegistration(
            debugBuild: true, explicitStagingOptIn: true, testHost: false, demo: true
        ))
    }
}
