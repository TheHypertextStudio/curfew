import CurfewKit
import SwiftUI

extension SettingsView {
    var protectedWorkPanel: some View {
        @Bindable var model = model
        return
            Group {
                Section {
                    CurfewSectionTitle(
                        title: "Delay shutdown",
                        subtitle: "Allow running work to finish within a time limit."
                    )
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
                        value: $model.settings.protectedWork.maximumDeferralMinutes,
                        range: 1 ... ProtectedWorkPolicy.deferralCeilingMinutes,
                        step: 5, usesMinutes: true
                    )
                    Text("Work can delay application termination and shutdown. "
                        + "It does not unlock the screen or change the schedule. "
                        + "Curfew resumes shutdown after the limit even if work is still running.")
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup(
                        "Commands that delay shutdown",
                        isExpanded: $showsDeferringCommands
                    ) {
                        Text("List commands that exit when their task finishes. A terminal or tmux "
                            +
                            "server may keep running and delay every shutdown "
                            + "until the limit expires.")
                            .font(CurfewTypography.body(13))
                            .foregroundStyle(CurfewTheme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                        processEditor(
                            "Command names, one per line", keyPath: \.deferringProcessNames
                        )
                    }
                }
                Section {
                    CurfewSectionTitle(title: "Skip application termination")
                    Text("Curfew skips the listed applications and processes when it requests "
                        + "termination before shutdown. A system shutdown still stops them.")
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup(
                        "Applications and processes",
                        isExpanded: $showsProtectedProcesses
                    ) {
                        processEditor(
                            "Application bundle identifiers", keyPath: \.protectedBundleIdentifiers
                        )
                        processEditor("Process names", keyPath: \.protectedProcessNames)
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
