import CurfewKit
import SwiftUI

extension SettingsView {
    var protectedWorkPanel: some View {
        @Bindable var model = model
        return Group {
            SettingsGroup(
                "Delay shutdown",
                footer: "Work can delay quitting apps and shutdown, up to the limit. "
                    + "It never unlocks the screen or changes the schedule."
            ) {
                SettingsToggleRow(
                    title: "Let AI assistants declare work in progress",
                    isOn: $model.settings.protectedWork.acceptsAgentClaims
                )
                SettingsToggleRow(
                    title: "Delay shutdown for remote sessions",
                    isOn: $model.settings.protectedWork.defersForRemoteSessions
                )
                SettingsValueRow(
                    title: "Maximum delay",
                    detail: "Shutdown goes ahead after this, even if work is still running.",
                    value: $model.settings.protectedWork.maximumDeferralMinutes,
                    range: 1 ... ProtectedWorkPolicy.deferralCeilingMinutes,
                    step: 5, usesMinutes: true
                )
                DisclosureGroup(isExpanded: $showsDeferringCommands) {
                    processEditor(
                        "Command names, one per line", keyPath: \.deferringProcessNames
                    )
                } label: {
                    SettingsRowLabel(
                        title: "Commands that delay shutdown",
                        detail: "List commands that exit when their task finishes. A terminal "
                            + "or tmux server would delay every shutdown until the limit."
                    )
                }
            }
            SettingsGroup(
                "Keep apps open",
                footer: "Curfew doesn't quit these before shutdown. "
                    + "Shutdown itself still stops them."
            ) {
                DisclosureGroup(isExpanded: $showsProtectedProcesses) {
                    processEditor(
                        "Application bundle identifiers", keyPath: \.protectedBundleIdentifiers
                    )
                    processEditor("Process names", keyPath: \.protectedProcessNames)
                } label: {
                    SettingsRowLabel(title: "Applications and processes")
                }
            }
        }
    }

    private func processEditor(
        _ title: String, keyPath: WritableKeyPath<ProtectedWorkPolicy, [String]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CurfewTypography.bodyEmphasis(12))
            TextEditor(text: protectedListBinding(keyPath))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 110)
                .background(CurfewTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(title)
        }
        .padding(.top, 8)
    }

    func protectedListBinding(
        _ keyPath: WritableKeyPath<ProtectedWorkPolicy, [String]>
    ) -> Binding<String> {
        Binding(
            get: { model.settings.protectedWork[keyPath: keyPath].joined(separator: "\n") },
            set: { newValue in
                model.settings.protectedWork[keyPath: keyPath] = newValue
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}
