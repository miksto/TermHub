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

    var body: some View {
        Section(isExpanded: $isExpanded) {
            ForEach(folderSessions) { session in
                SessionRowView(session: session, onRemove: {
                    sessionToRemove = session
                })
                .tag(session.id)
            }
        } header: {
            HStack {
                Label(folder.name, systemImage: "folder")
                    .font(.headline)
                if !folder.pathExists {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("Folder path no longer exists: \(folder.path)")
                }
                Spacer()
                Menu {
                    Button("New Shell") {
                        if !folder.pathExists {
                            appState.errorMessage = "Cannot create session: folder path no longer exists at \(folder.path)"
                            return
                        }
                        appState.addSession(
                            folderID: folder.id,
                            title: "\(folder.name) – Shell",
                            cwd: folder.path
                        )
                    }
                    if folder.isGitRepo {
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
                    Image(systemName: "ellipsis.circle")
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
                appState.removeSession(id: session.id)
                sessionToRemove = nil
            }
        } message: { session in
            if session.worktreePath != nil {
                Text("This will close the tmux session \"\(session.tmuxSessionName)\" and remove its worktree.")
            } else {
                Text("This will close the tmux session \"\(session.tmuxSessionName)\".")
            }
        }
    }
}
