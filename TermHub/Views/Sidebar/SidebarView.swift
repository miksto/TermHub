import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            List(selection: $state.selectedSessionID) {
                ForEach(appState.folders) { folder in
                    FolderSectionView(
                        folder: folder,
                        onRequestRemoveFolder: {
                            appState.pendingRemoveFolderID = folder.id
                        }
                    )
                }
                .onMove { from, to in
                    appState.moveFolder(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.sidebar)

            Button {
                appState.showAddFolderPanel()
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
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
    }
}
