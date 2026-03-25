import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            Text("Settings")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Form {
                Toggle("Option as Meta Key", isOn: $appState.optionAsMetaKey)
                Text("When enabled, the Option key sends ESC sequences (Meta) for terminal apps. When disabled, Option produces special characters (e.g. @ on Swedish keyboards).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Copy Claude settings to worktrees", isOn: $appState.copyClaudeSettingsToWorktrees)
                Text("Copies .claude/settings.local.json from the repo into new worktrees so Claude Code inherits the same permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Spacer()

            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 20)
        }
        .frame(width: 400, height: 320)
    }
}
