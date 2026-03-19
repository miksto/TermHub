import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var folderToRemove: ManagedFolder?

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
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

            Divider()

            Button {
                let panel = NSOpenPanel()
                panel.title = "Choose a folder"
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    appState.addFolder(path: url.path)
                }
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .navigationTitle("MuxManager")
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
                appState.removeFolder(id: folder.id)
                folderToRemove = nil
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
