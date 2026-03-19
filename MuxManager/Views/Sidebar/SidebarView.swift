import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddFolder = false
    @State private var folderToRemove: ManagedFolder?

    var body: some View {
        @Bindable var state = appState
        List(selection: $state.selectedSessionID) {
            ForEach(appState.folders) { folder in
                FolderSectionView(
                    folder: folder,
                    onRequestRemoveFolder: {
                        folderToRemove = folder
                    }
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MuxManager")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddFolder = true
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingAddFolder) {
            AddFolderSheet()
        }
        .sheet(
            isPresented: Binding(
                get: { appState.pendingWorktreeFolder != nil },
                set: { if !$0 { appState.pendingWorktreeFolder = nil } }
            )
        ) {
            if let folder = appState.pendingWorktreeFolder {
                BranchPickerSheet(folder: folder)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { appState.pendingNewBranchFolder != nil },
                set: { if !$0 { appState.pendingNewBranchFolder = nil } }
            )
        ) {
            if let folder = appState.pendingNewBranchFolder {
                NewBranchSheet(folder: folder)
            }
        }
        .alert(
            "Remove Folder",
            isPresented: Binding(
                get: { folderToRemove != nil },
                set: { if !$0 { folderToRemove = nil } }
            ),
            presenting: folderToRemove
        ) { folder in
            Button("Cancel", role: .cancel) {
                folderToRemove = nil
            }
            Button("Remove", role: .destructive) {
                removeFolderWithCleanup(folder)
                folderToRemove = nil
            }
        } message: { folder in
            let sessionCount = appState.sessions.filter { $0.folderID == folder.id }.count
            let worktreeCount = appState.sessions.filter { $0.folderID == folder.id && $0.worktreePath != nil }.count
            if worktreeCount > 0 {
                Text("This will kill \(sessionCount) tmux session(s) and remove \(worktreeCount) worktree(s) for \"\(folder.name)\".")
            } else {
                Text("This will kill \(sessionCount) tmux session(s) for \"\(folder.name)\".")
            }
        }
    }

    private func removeFolderWithCleanup(_ folder: ManagedFolder) {
        let folderSessions = appState.sessions.filter { $0.folderID == folder.id }
        for session in folderSessions {
            try? TmuxService.killSession(name: session.tmuxSessionName)
            if let worktreePath = session.worktreePath {
                try? GitService.removeWorktree(repoPath: folder.path, worktreePath: worktreePath)
            }
        }
        appState.removeFolder(id: folder.id)
    }
}
