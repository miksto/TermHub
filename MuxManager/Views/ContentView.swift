import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
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
                if let session = appState.selectedSession {
                    TerminalDetailView(session: session)
                } else {
                    Text("Select or create a session")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        // Keyboard shortcuts via hidden buttons
        .background(keyboardShortcutButtons)
        // Error alert
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
        // Close session confirmation
        .alert(
            "Close Session",
            isPresented: Binding(
                get: { appState.pendingCloseSessionID != nil },
                set: { if !$0 { appState.pendingCloseSessionID = nil } }
            ),
            presenting: appState.pendingCloseSessionID.flatMap { id in
                appState.sessions.first { $0.id == id }
            }
        ) { session in
            Button("Cancel", role: .cancel) {
                appState.pendingCloseSessionID = nil
            }
            Button("Close", role: .destructive) {
                appState.removeSession(id: session.id)
                appState.pendingCloseSessionID = nil
            }
        } message: { session in
            if session.worktreePath != nil {
                Text("This will close the tmux session \"\(session.tmuxSessionName)\" and remove its worktree.")
            } else {
                Text("This will close the tmux session \"\(session.tmuxSessionName)\".")
            }
        }
    }

    @ViewBuilder
    private var keyboardShortcutButtons: some View {
        // Cmd+T: New shell in currently selected folder
        Button("") {
            guard let session = appState.selectedSession,
                  let folder = appState.folders.first(where: { $0.id == session.folderID }) else { return }
            appState.addSession(
                folderID: folder.id,
                title: "\(folder.name) – Shell",
                cwd: folder.path
            )
        }
        .keyboardShortcut("t", modifiers: .command)
        .hidden()

        // Cmd+W: Close current session (with confirmation)
        Button("") {
            guard let session = appState.selectedSession else { return }
            appState.pendingCloseSessionID = session.id
        }
        .keyboardShortcut("w", modifiers: .command)
        .hidden()

        // Cmd+N: Add folder
        Button("") {
            appState.showingAddFolder = true
        }
        .keyboardShortcut("n", modifiers: .command)
        .hidden()
    }
}
