import SwiftUI

struct SettingsOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            panel
                .frame(width: 500, height: 620)
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
            VStack(spacing: 12) {
                // Terminal card
                sectionCard("Terminal") {
                    toggleRow(
                        "Option as Meta Key",
                        isOn: $appState.optionAsMetaKey,
                        caption: "When enabled, the Option key sends ESC sequences (Meta) for terminal apps. When disabled, Option produces special characters (e.g. @ on Swedish keyboards)."
                    )
                }

                // Integrations card
                sectionCard("Integrations") {
                    VStack(alignment: .leading, spacing: 10) {
                        toggleRow(
                            "Copy Claude settings to worktrees",
                            isOn: $appState.copyClaudeSettingsToWorktrees,
                            caption: "Copies .claude/settings.local.json from the repo into new worktrees so Claude Code inherits the same permissions."
                        )

                        Divider()

                        toggleRow(
                            "MCP Server",
                            isOn: $appState.mcpServerEnabled,
                            caption: "Runs a local MCP server so AI agents (e.g. Claude Code) can manage sessions, folders, and worktrees in TermHub."
                        )
                    }
                }

                // Bottom row: Assistant full width
                sectionCard("Assistant") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                        // Provider
                        GridRow {
                            formLabel("Provider")
                            Picker("Provider", selection: $appState.assistantProvider) {
                                ForEach(AssistantProvider.allCases, id: \.self) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        GridRow {
                            Color.clear.frame(width: 0, height: 0)
                            formCaption("Choose which CLI powers the assistant chat.")
                        }

                        GridRow { Color.clear.frame(height: 8).gridCellColumns(2) }

                        // Model
                        GridRow {
                            formLabel("Model")
                            Picker("Model", selection: $appState.assistantModel) {
                                ForEach(AppState.assistantModelOptions(for: appState.assistantProvider), id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        GridRow {
                            Color.clear.frame(width: 0, height: 0)
                            formCaption("Model passed to --model.")
                        }

                        GridRow { Color.clear.frame(height: 8).gridCellColumns(2) }

                        // Reasoning Effort
                        GridRow {
                            formLabel("Reasoning Effort")
                            Picker("Reasoning Effort", selection: $appState.assistantEffort) {
                                Text("Default").tag("")
                                ForEach(AppState.assistantEffortOptions(for: appState.assistantProvider).filter { !$0.isEmpty }, id: \.self) { effort in
                                    Text(effort.capitalized).tag(effort)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .disabled(!appState.assistantModelSupportsEffort)
                        }
                        GridRow {
                            Color.clear.frame(width: 0, height: 0)
                            formCaption(
                                appState.assistantModelSupportsEffort
                                    ? "Reasoning effort is passed to the selected assistant model."
                                    : "This model does not support reasoning effort; no effort argument will be sent."
                            )
                        }

                        GridRow { Color.clear.frame(height: 8).gridCellColumns(2) }

                        // Allowed Tools
                        GridRow {
                            formLabel("Allowed Tools")
                            TextField(appState.assistantAllowedToolsPlaceholder, text: $appState.assistantAllowedTools)
                                .textFieldStyle(.roundedBorder)
                                .font(.callout.monospaced())
                                .frame(maxWidth: .infinity)
                        }
                        GridRow {
                            Color.clear.frame(width: 0, height: 0)
                            formCaption(appState.assistantAllowedToolsHelpText)
                        }
                    }
                }
            }
            .padding(16)

            // Hidden button so Enter dismisses the panel
            Button("") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(label, isOn: isOn)
                .font(.callout)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.primary)
            .frame(width: 110, alignment: .trailing)
            .gridColumnAlignment(.trailing)
    }

    private func dismiss() {
        appState.showSettings = false
    }
}
