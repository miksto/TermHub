import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
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
        }
        .animation(.easeOut(duration: 0.15), value: appState.showCommandPalette)
        .sheet(isPresented: Binding(
            get: { appState.showKeyboardShortcuts },
            set: { appState.showKeyboardShortcuts = $0 }
        )) {
            KeyboardShortcutsSheet()
        }
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
