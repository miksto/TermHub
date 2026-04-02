import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var optionKeyDown = false
    @State private var flagsMonitor: Any?
    @State private var draggedSidebarItem: SidebarItem?
    @State private var dropTargetSidebarItem: SidebarItem?

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            List(selection: $state.selectedSessionID) {
                ForEach(appState.sidebarOrder, id: \.self) { item in
                    switch item {
                    case .folder(let folderID):
                        if let folder = appState.folders.first(where: { $0.id == folderID }) {
                            FolderSectionView(
                                folder: folder,
                                optionKeyDown: optionKeyDown,
                                onRequestRemoveFolder: {
                                    appState.pendingRemoveFolderID = folder.id
                                },
                                draggedSidebarItem: $draggedSidebarItem,
                                dropTargetSidebarItem: $dropTargetSidebarItem
                            )
                        }
                    case .group(let groupID):
                        if let group = appState.groups.first(where: { $0.id == groupID }) {
                            GroupSectionView(
                                group: group,
                                optionKeyDown: optionKeyDown,
                                draggedSidebarItem: $draggedSidebarItem,
                                dropTargetSidebarItem: $dropTargetSidebarItem
                            )
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .contextMenu {
                Button("Add Group") {
                    appState.addGroup(name: "New Group")
                }
            }

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
        .onAppear {
            guard flagsMonitor == nil else { return }
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                optionKeyDown = event.modifierFlags.contains(.option)
                return event
            }
        }
        .onDisappear {
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
        }
        .sheet(
            isPresented: Binding(
                get: { appState.pendingWorktreeFolder != nil },
                set: { if !$0 {
                    appState.pendingWorktreeFolder = nil
                    appState.pendingWorktreeSandbox = nil
                } }
            )
        ) {
            if let folder = appState.pendingWorktreeFolder {
                BranchPickerSheet(folder: folder, initialSandbox: appState.pendingWorktreeSandbox)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { appState.pendingNewBranchFolder != nil },
                set: { if !$0 {
                    appState.pendingNewBranchFolder = nil
                    appState.pendingNewBranchSandbox = nil
                } }
            )
        ) {
            if let folder = appState.pendingNewBranchFolder {
                NewBranchSheet(folder: folder, initialSandbox: appState.pendingNewBranchSandbox)
            }
        }
    }
}
