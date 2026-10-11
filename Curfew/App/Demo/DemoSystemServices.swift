#if DEBUG
    import CurfewKit
    import ServiceManagement

    /// In-memory registrations keep interactive capture controls away from launchd.
    final class DemoAppService: AppServiceControlling {
        var status: SMAppService.Status = .notRegistered
        func register() throws {
            status = .enabled
        }

        func unregister() throws {
            status = .notRegistered
        }
    }

    /// Capture launches never prompt for, or change, real Accessibility access.
    struct DemoAccessibilityAuthorization: AccessibilityAuthorizing {
        func isTrusted() -> Bool {
            true
        }

        func promptForTrust() -> Bool {
            true
        }
    }
#endif

#if DEBUG
    import Foundation

    /// Synthetic reflections for journal screenshots; never reads the user's journal.
    final class DemoReflectionRecorder: ReflectionRecording {
        private var entries: [Reflection]
        private(set) var mutationCount = 0

        init(now: Date) {
            self.entries = [Reflection(timestamp: now, gate: .evening, answers: [
                ReflectionAnswer(
                    promptID: UUID(),
                    promptTextSnapshot: "What went well today?",
                    value: .text("Finished the project and made time for a walk.")
                )
            ])]
        }

        func record(_ reflection: Reflection) {
            entries.append(reflection); mutationCount += 1
        }

        func reflections(in range: ClosedRange<Date>) -> [Reflection] {
            entries.filter { range.contains($0.timestamp) }
        }

        func trim(olderThan seconds: TimeInterval, now: Date) {
            entries.removeAll { now.timeIntervalSince($0.timestamp) > seconds }
        }
    }

    /// No real XPC calls, including when exercising removal of a demo registration.
    struct DemoDaemonRPC: PrivilegedDaemonRPCControlling {
        func armLockout(_ record: LockoutDeadlineRecord) async throws {}
        func heartbeat(lockoutID: UUID) async throws {}
        func completeLockout(lockoutID: UUID, reason: PrivilegedCompletionReason) async throws {}
        func status() async throws -> PrivilegedDaemonStatus {
            throw PrivilegedDaemonRPCError
                .unavailable
        }

        func prepareForUninstall() async throws {}
    }
#endif
