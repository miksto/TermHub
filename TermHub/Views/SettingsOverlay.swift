import SwiftUI

struct SettingsOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            panel
                .frame(width: 460, height: 420)
                .background(.ultraThickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 30, y: 10)
        }
    }

    private var panel: some View {
        @Bindable var appState = appState

        return VStack(spacing: 0) {
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

                Toggle("MCP Server", isOn: $appState.mcpServerEnabled)
                Text("Runs a local MCP server so AI agents (e.g. Claude Code) can manage sessions, folders, and worktrees in TermHub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Assistant Working Directory", text: $appState.assistantWorkingDirectory)
                    .textFieldStyle(.roundedBorder)
                Text("Claude runs from this path when using the dedicated assistant. Default is the app launch directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .scrollDisabled(false)

            Spacer()

            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 20)
        }
    }

    private func dismiss() {
        appState.showSettings = false
    }
}
