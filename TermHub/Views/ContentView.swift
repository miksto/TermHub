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
                    SandboxToolbarButton()
                }
            }
            .sheet(isPresented: Binding(
                get: { appState.showKeyboardShortcuts },
                set: { appState.showKeyboardShortcuts = $0 }
            )) {
                KeyboardShortcutsSheet()
            }
            .modifier(ContentViewAlerts())
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

            if appState.isSessionSwitcherActive {
                SessionSwitcherOverlay()
                    .transition(.opacity)
            }

            if appState.showSandboxManager {
                SandboxManagerOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: appState.showCommandPalette)
        .animation(.easeOut(duration: 0.1), value: appState.isSessionSwitcherActive)
        .animation(.easeOut(duration: 0.15), value: appState.showSandboxManager)
    }

    private func installSessionSwitcherMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape dismisses overlays before the terminal can consume it
            if event.keyCode == 53 {
                if appState.showSandboxManager {
                    appState.showSandboxManager = false
                    return nil
                }
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
    @State private var sandboxNameInput: String = ""

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
            .alert(
                "Configure Docker Sandbox",
                isPresented: Binding(
                    get: { appState.pendingSandboxConfigFolderID != nil },
                    set: { if !$0 { appState.pendingSandboxConfigFolderID = nil } }
                ),
                presenting: appState.pendingSandboxConfigFolderID.flatMap { id in
                    appState.folders.first(where: { $0.id == id })
                }
            ) { folder in
                TextField("Sandbox name", text: $sandboxNameInput)
                Button("Cancel", role: .cancel) {
                    appState.pendingSandboxConfigFolderID = nil
                }
                Button("Save") {
                    let trimmed = sandboxNameInput.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && !DockerSandboxService.isValidSandboxName(trimmed) {
                        appState.errorMessage = "Invalid sandbox name. Use only letters, numbers, dots, hyphens, and underscores."
                    } else {
                        appState.setSandboxName(trimmed.isEmpty ? nil : trimmed, forFolder: folder.id)
                    }
                    appState.pendingSandboxConfigFolderID = nil
                }
            } message: { folder in
                Text("Enter the Docker sandbox name for \"\(folder.name)\".")
            }
            .onChange(of: appState.pendingSandboxConfigFolderID) { _, newValue in
                if let id = newValue, let folder = appState.folders.first(where: { $0.id == id }) {
                    sandboxNameInput = folder.sandboxName ?? ""
                }
            }
    }
}

// MARK: - Sandbox Toolbar Button

struct SandboxToolbarButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let hasRunning = appState.sandboxes.contains { $0.isRunning }
        let hasConfigured = appState.folders.contains { $0.hasSandbox }
        let color: Color = hasRunning ? .green : hasConfigured ? .orange : .secondary

        Button {
            appState.showSandboxManager.toggle()
        } label: {
            Image(systemName: "shippingbox")
                .foregroundStyle(color)
        }
        .help("Sandbox Manager")
    }
}
