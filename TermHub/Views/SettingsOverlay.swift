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

            ScrollView {
                // Content
                VStack(spacing: 12) {
                    // Terminal card
                    sectionCard("Terminal") {
                        VStack(alignment: .leading, spacing: 10) {
                            toggleRow(
                                "Option as Meta Key",
                                isOn: $appState.optionAsMetaKey,
                                caption: "When enabled, the Option key sends ESC sequences (Meta) for terminal apps. When disabled, Option produces special characters (e.g. @ on Swedish keyboards)."
                            )

                            Divider()

                            toggleRow(
                                "Send TTY size to sandbox terminals",
                                isOn: $appState.sendTTYSizeToSandboxTerminals,
                                caption: "Sends the current rows and columns to sandbox terminals when they start and when the terminal view is resized."
                            )
                        }
                    }

                    // Navigation card
                    sectionCard("Navigation") {
                        VStack(alignment: .leading, spacing: 10) {
                            toggleRow(
                                "Reveal selected session in sidebar when using Ctrl+Tab",
                                isOn: $appState.revealSelectedSessionInSidebarOnCtrlTab,
                                caption: "When enabled, the sidebar expands and scrolls to the session chosen with Ctrl+Tab. Cmd+P and Cmd+J always reveal the selected session."
                            )
                        }
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
                        VStack(alignment: .leading, spacing: 12) {
                            formRow("Provider", caption: "Choose which CLI powers the assistant chat.") {
                                Picker("Provider", selection: $appState.assistantProvider) {
                                    ForEach(AssistantProvider.allCases, id: \.self) { provider in
                                        Text(provider.displayName).tag(provider)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            formRow("Model", caption: "Model passed to --model.") {
                                Picker("Model", selection: $appState.assistantModel) {
                                    ForEach(AppState.assistantModelOptions(for: appState.assistantProvider), id: \.self) { model in
                                        Text(AppState.assistantModelDisplayName(for: appState.assistantProvider, model: model)).tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            formRow("CLI Path") {
                                HStack(spacing: 8) {
                                    TextField(
                                        "/path/to/\(appState.assistantProvider.commandName)",
                                        text: $appState.assistantCLIPath
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .font(.callout.monospaced())

                                    Button("Detect") {
                                        appState.detectAssistantCLIPath()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } captionContent: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(appState.assistantCLIPathIsAvailable ? .green : .orange)
                                        .frame(width: 7, height: 7)
                                    Text(
                                        appState.assistantCLIPathIsAvailable
                                            ? "Detected and executable. Use Detect to restore the automatic path."
                                            : "Path not found or not executable."
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }

                            formRow(
                                "Reasoning Effort",
                                caption: appState.assistantModelSupportsEffort
                                    ? "Reasoning effort is passed to the selected assistant model."
                                    : "This model does not support reasoning effort; no effort argument will be sent."
                            ) {
                                Picker("Reasoning Effort", selection: $appState.assistantEffort) {
                                    Text("Default").tag("")
                                ForEach(
                                    AppState.assistantEffortOptions(
                                        for: appState.assistantProvider,
                                        model: appState.assistantModel
                                    ).filter { !$0.isEmpty },
                                    id: \.self
                                ) { effort in
                                        Text(effort.capitalized).tag(effort)
                                    }
                                }
                                .pickerStyle(.menu)
                                .disabled(!appState.assistantModelSupportsEffort)
                            }

                            formRow("Allowed Tools", caption: appState.assistantAllowedToolsHelpText) {
                                TextField(appState.assistantAllowedToolsPlaceholder, text: $appState.assistantAllowedTools)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.callout.monospaced())
                            }

                            if appState.assistantProvider == .codex {
                                codexCapabilities
                            }
                        }
                    }
                }
                .padding(16)
            }

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

    private var codexCapabilities: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 2)

            Text("Available to Claude")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            capabilityRow(
                title: "MCPs",
                icon: "server.rack",
                value: codexMCPNames.isEmpty
                    ? "None configured"
                    : codexMCPNames.joined(separator: ", ")
            )

            capabilityRow(
                title: "Skills",
                icon: "wand.and.stars",
                value: codexSkillNames.isEmpty
                    ? "None detected in ~/.codex/skills"
                    : codexSkillNames.joined(separator: ", ")
            )
        }
        .padding(.top, 2)
    }

    private func capabilityRow(title: String, icon: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.callout)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var codexMCPNames: [String] {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
        guard let config = try? String(contentsOf: configURL, encoding: .utf8) else { return [] }

        return config
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let prefix = "[mcp_servers."
                guard line.hasPrefix(prefix), line.hasSuffix("]") else { return nil }
                return String(line.dropFirst(prefix.count).dropLast())
            }
            .filter { !$0.contains(".") }
            .sorted()
    }

    private var codexSkillNames: [String] {
        let skillsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/skills", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: skillsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && FileManager.default.fileExists(atPath: url.appendingPathComponent("SKILL.md").path)
            }
            .map(\.lastPathComponent)
            .sorted()
    }

    private func formRow<Control: View, Caption: View>(
        _ label: String,
        @ViewBuilder control: () -> Control,
        @ViewBuilder captionContent: () -> Caption
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                formLabel(label)
                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 12) {
                Color.clear.frame(width: 110)
                captionContent()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func formRow<Control: View>(
        _ label: String,
        caption: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        formRow(label, control: control) {
            formCaption(caption)
        }
    }

    private func formRow<Control: View>(
        _ label: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        formRow(label, control: control) {
            EmptyView()
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
    }

    private func dismiss() {
        appState.showSettings = false
    }
}
