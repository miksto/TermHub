import SwiftUI

struct SettingsOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            panel
                .frame(width: 460, height: 560)
                .background(.ultraThickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 30, y: 10)
        }
    }

    private var panel: some View {
        @Bindable var appState = appState

        return VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Terminal section
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Terminal")

                        settingRow {
                            Toggle("Option as Meta Key", isOn: $appState.optionAsMetaKey)
                                .font(.callout)
                        } caption: {
                            "When enabled, the Option key sends ESC sequences (Meta) for terminal apps. When disabled, Option produces special characters (e.g. @ on Swedish keyboards)."
                        }
                    }

                    Divider()

                    // Integrations section
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader("Integrations")

                        settingRow {
                            Toggle("Copy Claude settings to worktrees", isOn: $appState.copyClaudeSettingsToWorktrees)
                                .font(.callout)
                        } caption: {
                            "Copies .claude/settings.local.json from the repo into new worktrees so Claude Code inherits the same permissions."
                        }

                        settingRow {
                            Toggle("MCP Server", isOn: $appState.mcpServerEnabled)
                                .font(.callout)
                        } caption: {
                            "Runs a local MCP server so AI agents (e.g. Claude Code) can manage sessions, folders, and worktrees in TermHub."
                        }

                    }

                    Divider()

                    // Assistant section
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Assistant")

                        settingRow {
                            Picker("Provider", selection: $appState.assistantProvider) {
                                ForEach(AssistantProvider.allCases, id: \.self) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)
                        } caption: {
                            "Choose which CLI powers the assistant chat."
                        }

                        settingRow {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Allowed Tools")
                                    .font(.callout)
                                TextField(appState.assistantAllowedToolsPlaceholder, text: $appState.assistantAllowedTools)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.callout.monospaced())
                            }
                        } caption: {
                            appState.assistantAllowedToolsHelpText
                        }

                        settingRow {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Model")
                                    .font(.callout)
                                TextField(
                                    AppState.defaultAssistantModel(for: appState.assistantProvider),
                                    text: $appState.assistantModel
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(.callout.monospaced())
                            }
                        } caption: {
                            "Model ID passed to --model. Leave empty to use the default."
                        }

                        settingRow {
                            HStack {
                                Text("Reasoning Effort")
                                    .font(.callout)
                                Spacer()
                                Picker("", selection: $appState.assistantEffort) {
                                    Text("Default").tag("")
                                    Text("Low").tag("low")
                                    Text("Medium").tag("medium")
                                    Text("High").tag("high")
                                    Text("XHigh").tag("xhigh")
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 260)
                            }
                        } caption: {
                            "Reasoning effort passed to --effort. Default uses the provider's built-in level."
                        }
                    }
                }
                .padding(20)
            }

            // Hidden button so Enter dismisses the panel
            Button("") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func settingRow<Content: View>(@ViewBuilder content: () -> Content, caption: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            Text(caption())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func dismiss() {
        appState.showSettings = false
    }
}
