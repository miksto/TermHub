import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?

    var body: some View {
        mainContent
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 4) {
                        Button {
                            appState.showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .help("Settings")

                        SandboxToolbarButton()
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { appState.showKeyboardShortcuts },
                set: { appState.showKeyboardShortcuts = $0 }
            )) {
                KeyboardShortcutsSheet()
            }
            .onChange(of: appState.showSettings) { _, show in
                if show {
                    if let window = NSApp.mainWindow {
                        SettingsPanel.show(in: window, appState: appState)
                    }
                } else {
                    SettingsPanel.dismiss()
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { appState.pendingSandboxPickerContext != nil },
                    set: { if !$0 { appState.pendingSandboxPickerContext = nil } }
                )
            ) {
                if let ctx = appState.pendingSandboxPickerContext {
                    ShellSandboxPickerSheet(
                        folderID: ctx.folderID,
                        folderName: ctx.folderName,
                        cwd: ctx.cwd,
                        worktreePath: ctx.worktreePath,
                        branchName: ctx.branchName,
                        initialSandboxName: appState.lastUsedSandboxName
                    )
                }
            }
            .modifier(ContentViewAlerts())
            .onChange(of: appState.showSandboxManager) { _, show in
                if show {
                    if let window = NSApp.mainWindow {
                        SandboxManagerPanel.show(in: window, appState: appState)
                    }
                } else {
                    SandboxManagerPanel.dismiss()
                }
            }
            .onAppear { installSessionSwitcherMonitors() }
            .onDisappear { removeSessionSwitcherMonitors() }
    }

    private var mainContent: some View {
        ZStack {
            VStack(spacing: 0) {
                if !appState.tmuxAvailable {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("tmux not found — sessions won't persist across restarts")
                    }
                    .font(.callout)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.85))
                }

                NavigationSplitView {
                    SidebarView()
                } detail: {
                    if appState.selectedSessionID != nil {
                        TerminalContainerView(selectedSessionID: appState.selectedSessionID)
                    } else {
                        Text("Select or create a session")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationSplitViewStyle(.balanced)
            }

            if appState.showCommandPalette {
                CommandPaletteOverlay()
                    .transition(.opacity)
            }

            if appState.showAssistant {
                AssistantOverlay()
                    .transition(.opacity)
            }

            if appState.isSessionSwitcherActive {
                SessionSwitcherOverlay()
                    .transition(.opacity)
            }

        }
        .animation(.easeOut(duration: 0.15), value: appState.showCommandPalette)
        .animation(.easeOut(duration: 0.15), value: appState.showAssistant)
        .animation(.easeOut(duration: 0.1), value: appState.isSessionSwitcherActive)
    }

    private func installSessionSwitcherMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape dismisses overlays before the terminal can consume it

            // Ctrl+Space toggles assistant
            if event.keyCode == 49, event.modifierFlags.contains(.control) {
                appState.toggleAssistant()
                return nil
            }

            // Ctrl+Tab (keyCode 48 = Tab)
            guard event.keyCode == 48,
                  event.modifierFlags.contains(.control) else {
                return event
            }
            let reverse = event.modifierFlags.contains(.shift)
            if appState.isSessionSwitcherActive {
                if reverse {
                    appState.reverseSessionSwitcher()
                } else {
                    appState.advanceSessionSwitcher()
                }
            } else {
                if reverse {
                    // For Ctrl+Shift+Tab when not active, begin and immediately reverse
                    appState.beginSessionSwitcher()
                } else {
                    appState.beginSessionSwitcher()
                }
            }
            return nil
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            if appState.isSessionSwitcherActive,
               !event.modifierFlags.contains(.control) {
                appState.commitSessionSwitcher()
            }
            return event
        }
    }

    private func removeSessionSwitcherMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
    }
}

// MARK: - Alerts

private struct ContentViewAlerts: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .alert(
                "Error",
                isPresented: Binding(
                    get: { appState.errorMessage != nil },
                    set: { if !$0 { appState.errorMessage = nil } }
                ),
                presenting: appState.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {
                    appState.errorMessage = nil
                }
            } message: { message in
                Text(message)
            }
            .alert(
                "Remove Folder",
                isPresented: Binding(
                    get: { appState.pendingRemoveFolderID != nil },
                    set: { if !$0 { appState.pendingRemoveFolderID = nil } }
                ),
                presenting: appState.pendingRemoveFolderID.flatMap { id in
                    appState.folders.first(where: { $0.id == id })
                }
            ) { folder in
                Button("Cancel", role: .cancel) {
                    appState.pendingRemoveFolderID = nil
                }
                Button("Remove", role: .destructive) {
                    appState.removeFolder(id: folder.id)
                    appState.pendingRemoveFolderID = nil
                }
            } message: { folder in
                let sessionCount = appState.sessions.filter { $0.folderID == folder.id }.count
                let worktreeCount = appState.sessions.filter { $0.folderID == folder.id && $0.worktreePath != nil }.count
                if worktreeCount > 0 {
                    Text("This will close \(sessionCount) tmux session(s) and remove \(worktreeCount) worktree(s) for \"\(folder.name)\".")
                } else {
                    Text("This will close \(sessionCount) tmux session(s) for \"\(folder.name)\".")
                }
            }
    }
}

// MARK: - Sandbox Toolbar Button

struct SandboxToolbarButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let hasRunning = appState.sandboxes.contains { $0.isRunning }
        let hasSandboxSessions = appState.sessions.contains { $0.isSandboxSession }
        let color: Color = hasRunning ? .green : hasSandboxSessions ? .orange : .secondary

        Button {
            appState.showSandboxManager.toggle()
        } label: {
            Image(systemName: "shippingbox")
                .foregroundStyle(color)
        }
        .help("Sandbox Manager")
    }
}

struct AssistantOverlay: View {
    @Environment(AppState.self) private var appState
    @State private var input = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    appState.showAssistant = false
                }

            VStack(spacing: 0) {
                header
                Divider()
                transcript
                Divider()
                composer
            }
            .frame(width: 760, height: 520)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .onAppear {
                isInputFocused = true
                input = appState.assistantInputText
            }
            .onKeyPress(.escape) {
                appState.showAssistant = false
                return .handled
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TermHub Assistant")
                    .font(.headline)
                if let status = appState.assistantStatusMessage, !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(appState.assistantIsBusy ? "Claude is responding…" : "Connected to Claude")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Restart") {
                appState.restartAssistantSession()
            }
            .disabled(appState.assistantIsBusy)

            Button("Clear") {
                appState.clearAssistantChat()
            }

            Button("Close") {
                appState.showAssistant = false
            }
        }
        .padding(12)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if appState.assistantMessages.isEmpty {
                        Text("Ask anything. Claude can use the TermHub MCP server to manage sessions, worktrees, and sandboxes.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 18)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(appState.assistantMessages) { message in
                            assistantMessageRow(message)
                                .id(message.id)
                        }
                    }
                }
                .padding(12)
            }
            .onChange(of: appState.assistantMessages.count) { _, _ in
                if let id = appState.assistantMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func assistantMessageRow(_ message: AssistantMessage) -> some View {
        let isUser = message.role == .user
        let foreground: Color
        let background: Color
        switch message.role {
        case .user:
            foreground = .white
            background = Color.accentColor.opacity(0.85)
        case .assistant:
            foreground = .primary
            background = Color.gray.opacity(0.15)
        case .system:
            foreground = .secondary
            background = Color.gray.opacity(0.12)
        case .error:
            foreground = .red
            background = Color.red.opacity(0.12)
        }

        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .textSelection(.enabled)
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 620, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Prompt Claude…", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .lineLimit(1...5)
                .onSubmit {
                    submitPrompt()
                }
                .onChange(of: input) { _, newValue in
                    appState.assistantInputText = newValue
                }

            Button("Send") {
                submitPrompt()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }

    private func submitPrompt() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.sendAssistantPrompt(trimmed)
        input = ""
    }
}
