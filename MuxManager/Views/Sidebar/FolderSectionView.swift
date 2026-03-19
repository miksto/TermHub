import SwiftUI

struct FolderSectionView: View {
    @Environment(AppState.self) private var appState
    let folder: ManagedFolder
    var onRequestRemoveFolder: () -> Void

    @State private var isExpanded = true
    @State private var sessionToRemove: TerminalSession?

    private var folderSessions: [TerminalSession] {
        appState.sessions.filter { $0.folderID == folder.id }
    }

    private var isGitRepo: Bool {
        GitService.isGitRepo(path: folder.path)
    }

    var body: some View {
        Section(isExpanded: $isExpanded) {
            ForEach(folderSessions) { session in
                SessionRowView(session: session) {
                    sessionToRemove = session
                }
                .tag(session.id)
            }
        } header: {
            HStack {
                Label(folder.name, systemImage: "folder")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("New Shell") {
                        appState.addSession(
                            folderID: folder.id,
                            title: "\(folder.name) – Shell",
                            cwd: folder.path
                        )
                    }
                    if isGitRepo {
                        Button("Worktree from Branch") {
                            appState.pendingWorktreeFolder = folder
                        }
                        Button("New Branch Worktree") {
                            appState.pendingNewBranchFolder = folder
                        }
                    }
                    Divider()
                    Button("Remove Folder", role: .destructive) {
                        onRequestRemoveFolder()
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .alert(
            "Remove Session",
            isPresented: Binding(
                get: { sessionToRemove != nil },
                set: { if !$0 { sessionToRemove = nil } }
            ),
            presenting: sessionToRemove
        ) { session in
            Button("Cancel", role: .cancel) {
                sessionToRemove = nil
            }
            Button("Remove", role: .destructive) {
                removeSessionWithCleanup(session)
                sessionToRemove = nil
            }
        } message: { session in
            if session.worktreePath != nil {
                Text("This will kill the tmux session \"\(session.tmuxSessionName)\" and remove its worktree.")
            } else {
                Text("This will kill the tmux session \"\(session.tmuxSessionName)\".")
            }
        }
    }

    private func removeSessionWithCleanup(_ session: TerminalSession) {
        try? TmuxService.killSession(name: session.tmuxSessionName)
        if let worktreePath = session.worktreePath {
            try? GitService.removeWorktree(repoPath: folder.path, worktreePath: worktreePath)
        }
        appState.removeSession(id: session.id)
    }
}
