@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Gating tests for the MCP control plane (Track B, task B2).
///
/// The MCP request monitor / socket pair must start only when BOTH the
/// build-level `featureFlags.mcpServerEnabled` and the user-level
/// `settings.mcpEnabled` are on. The default test host ships
/// `FeatureFlags.default` (MCP flag off) with `settings.mcpEnabled == true`,
/// so the runtime must stay dormant until the flag is flipped.
@MainActor
struct MCPGatingTests {
    @Test("MCP runtime stays dormant under default flags even when the setting is on")
    func dormantUnderDefaultFlags() {
        let model = makeModel(featureFlags: .default)
        // Default settings ship mcpEnabled == true, so this isolates the
        // feature-flag gate: the flag is off, so the runtime must not start.
        #expect(model.settings.mcpEnabled)
        #expect(!model.mcpRequestMonitor.isStarted)
    }

    @Test("MCP runtime starts at init when both the flag and the setting are on")
    func startsWhenFlagAndSettingOn() {
        let model = makeModel(featureFlags: mcpOnlyFlags)
        #expect(model.settings.mcpEnabled)
        #expect(model.mcpRequestMonitor.isStarted)
    }

    @Test("MCP runtime stays dormant when the flag is on but the user disabled it")
    func dormantWhenSettingOffEvenWithFlag() {
        let model = makeModel(featureFlags: mcpOnlyFlags, mcpEnabled: false)
        #expect(!model.settings.mcpEnabled)
        #expect(!model.mcpRequestMonitor.isStarted)
    }

    @Test("Toggling the setting on starts the runtime only while the flag is on")
    func togglingSettingRespectsFlag() {
        // Flag off: toggling the user setting must never start the runtime.
        let flagOff = makeModel(featureFlags: .default, mcpEnabled: false)
        flagOff.settings.mcpEnabled = true
        #expect(!flagOff.mcpRequestMonitor.isStarted)

        // Flag on: toggling the user setting drives the runtime start/stop.
        let flagOn = makeModel(featureFlags: mcpOnlyFlags, mcpEnabled: false)
        #expect(!flagOn.mcpRequestMonitor.isStarted)
        flagOn.settings.mcpEnabled = true
        #expect(flagOn.mcpRequestMonitor.isStarted)
        flagOn.settings.mcpEnabled = false
        #expect(!flagOn.mcpRequestMonitor.isStarted)
    }

    // MARK: - Helpers

    /// Feature flags with only the MCP server enabled; every other deferred
    /// module stays off so the runtime under test is isolated.
    private var mcpOnlyFlags: FeatureFlags {
        var flags = FeatureFlags.default
        flags.mcpServerEnabled = true
        return flags
    }

    private func makeModel(
        featureFlags: FeatureFlags,
        mcpEnabled: Bool = true
    ) -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.mcp-gating.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.mcpEnabled = mcpEnabled
        store.save(settings)
        return CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            featureFlags: featureFlags,
            activityRecorder: NullActivityRecording()
        )
    }
}
