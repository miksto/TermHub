import SwiftUI

struct GroupSectionView: View {
    @Environment(AppState.self) private var appState
    let group: FolderGroup
    var optionKeyDown: Bool = false
    @Binding var draggedSidebarItem: SidebarItem?
    @Binding var dropTargetSidebarItem: SidebarItem?
    var visibleFolderIDs: Set<UUID>? = nil
    var forceExpanded: Bool = false

    private var groupFolders: [ManagedFolder] {
        group.folderIDs.compactMap { folderID in
            appState.folders.first { $0.id == folderID }
        }
        .filter { visibleFolderIDs?.contains($0.id) ?? true }
    }

    var body: some View {
        GroupHeaderRow(
            group: group,
            onRequestRemoveGroup: {
                appState.removeGroup(id: group.id)
            },
            draggedSidebarItem: $draggedSidebarItem,
            dropTargetSidebarItem: $dropTargetSidebarItem,
            isExpanded: forceExpanded || group.isExpanded
        )
        .selectionDisabled()
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 2, trailing: 0))

        if forceExpanded || group.isExpanded {
            ForEach(groupFolders) { folder in
                FolderSectionView(
                    folder: folder,
                    optionKeyDown: optionKeyDown,
                    onRequestRemoveFolder: {
                        appState.pendingRemoveFolderID = folder.id
                    },
                    draggedSidebarItem: $draggedSidebarItem,
                    dropTargetSidebarItem: $dropTargetSidebarItem,
                    isInsideGroup: true,
                    forceExpanded: forceExpanded
                )
            }
        }
    }
}
