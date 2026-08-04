import Foundation
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var optionKeyDown = false
    @State private var flagsMonitor: Any?
    @State private var draggedSidebarItem: SidebarItem?
    @State private var dropTargetSidebarItem: SidebarItem?
    @State private var projectSearchText = ""

    private var isSearchingProjects: Bool {
        !projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var matchingFolderIDs: Set<UUID> {
        guard isSearchingProjects else {
            return Set(appState.folders.map(\.id))
        }

        return Set(appState.folders.compactMap { folder in
            ProjectNameSearch.matches(query: projectSearchText, projectName: folder.name)
                ? folder.id
                : nil
        })
    }

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search projects", text: $projectSearchText)
                    .textFieldStyle(.plain)

                if !projectSearchText.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") {
                        projectSearchText = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear project search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            ScrollViewReader { proxy in
                List(selection: $state.selectedSessionID) {
                    if isSearchingProjects && matchingFolderIDs.isEmpty {
                        ContentUnavailableView.search(text: projectSearchText)
                            .listRowBackground(Color.clear)
                            .selectionDisabled()
                    }

                    ForEach(appState.sidebarOrder, id: \.self) { item in
                        switch item {
                        case .folder(let folderID):
                            if let folder = appState.folders.first(where: { $0.id == folderID }),
                               matchingFolderIDs.contains(folder.id) {
                                FolderSectionView(
                                    folder: folder,
                                    optionKeyDown: optionKeyDown,
                                    onRequestRemoveFolder: {
                                        appState.pendingRemoveFolderID = folder.id
                                    },
                                    draggedSidebarItem: $draggedSidebarItem,
                                    dropTargetSidebarItem: $dropTargetSidebarItem,
                                    forceExpanded: isSearchingProjects
                                )
                            }
                        case .group(let groupID):
                            if let group = appState.groups.first(where: { $0.id == groupID }),
                               group.folderIDs.contains(where: matchingFolderIDs.contains) {
                                GroupSectionView(
                                    group: group,
                                    optionKeyDown: optionKeyDown,
                                    draggedSidebarItem: $draggedSidebarItem,
                                    dropTargetSidebarItem: $dropTargetSidebarItem,
                                    visibleFolderIDs: matchingFolderIDs,
                                    forceExpanded: isSearchingProjects
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
                .onChange(of: appState.sidebarRevealSessionID) { _, sessionID in
                    guard let sessionID else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(sessionID, anchor: .center)
                        }
                        appState.clearSidebarRevealRequest()
                    }
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
        .sheet(
            isPresented: Binding(
                get: { appState.pendingCheckoutBranchFolder != nil },
                set: { if !$0 { appState.pendingCheckoutBranchFolder = nil } }
            )
        ) {
            if let folder = appState.pendingCheckoutBranchFolder {
                NewCheckedOutBranchSheet(folder: folder)
            }
        }
    }
}
