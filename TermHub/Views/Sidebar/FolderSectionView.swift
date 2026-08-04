import SwiftUI

struct FolderSectionView: View {
    @Environment(AppState.self) private var appState
    let folder: ManagedFolder
    var optionKeyDown: Bool = false
    var onRequestRemoveFolder: () -> Void
    @Binding var draggedSidebarItem: SidebarItem?
    @Binding var dropTargetSidebarItem: SidebarItem?
    var isInsideGroup: Bool = false
    var forceExpanded: Bool = false

    private var plainSessionIDs: [UUID] {
        folder.sessionIDs.filter { id in
            appState.sessions.first(where: { $0.id == id })?.worktreePath == nil
        }
    }

    private var baseLeading: CGFloat { isInsideGroup ? 14 : 0 }

    @ViewBuilder
    var body: some View {
        // Read sessionListVersion to re-evaluate when sessions are added/removed.
        let _ = appState.sessionListVersion

        FolderHeaderRow(
            folder: folder,
            onRequestRemoveFolder: onRequestRemoveFolder,
            draggedSidebarItem: $draggedSidebarItem,
            dropTargetSidebarItem: $dropTargetSidebarItem,
            isInsideGroup: isInsideGroup,
            isExpanded: forceExpanded || folder.isExpanded
        )
        .selectionDisabled()
        .listRowInsets(EdgeInsets(top: 4, leading: baseLeading, bottom: 2, trailing: 0))

        if forceExpanded || folder.isExpanded {
            // Plain shell sessions
            ForEach(plainSessionIDs, id: \.self) { sessionID in
                SessionRowView(sessionID: sessionID, onRemove: {
                    appState.removeSession(id: sessionID)
                })
                .id(sessionID)
                .tag(sessionID)
                .listRowInsets(EdgeInsets(top: 0, leading: baseLeading + 14, bottom: 0, trailing: 0))
            }

            // Action buttons for folder-level actions
            HStack(spacing: 6) {
                ShellSplitButton(
                    folderID: folder.id,
                    folderName: folder.name,
                    cwd: folder.path,
                    optionKeyDown: optionKeyDown,
                    pathExists: folder.pathExists
                )

                if folder.isGitRepo {
                    Button {
                        if NSEvent.modifierFlags.contains(.option) {
                            appState.pendingWorktreeSandbox = appState.lastUsedSandboxName
                        }
                        appState.pendingWorktreeFolder = folder
                    } label: {
                        SandboxSwappableLabel(
                            title: "Branch",
                            systemImage: "arrow.triangle.branch",
                            showSandboxIcon: optionKeyDown && !appState.sandboxes.isEmpty
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        if NSEvent.modifierFlags.contains(.option) {
                            appState.pendingNewBranchSandbox = appState.lastUsedSandboxName
                        }
                        appState.pendingNewBranchFolder = folder
                    } label: {
                        SandboxSwappableLabel(
                            title: "New",
                            systemImage: "plus",
                            showSandboxIcon: optionKeyDown && !appState.sandboxes.isEmpty
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if appState.worktreeDiscoveryInProgress.contains(folder.id),
                       appState.worktrees(for: folder.id).isEmpty {
                        ProgressView()
                            .controlSize(.small)
                    } else if let error = appState.worktreeDiscoveryErrors[folder.id] {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help(error)
                    }
                }
            }
            .padding(.top, 2)
            .listRowInsets(EdgeInsets(top: 0, leading: baseLeading + 14, bottom: 0, trailing: 0))
            .selectionDisabled()

            // Worktree groups
            ForEach(appState.worktrees(for: folder.id)) { worktree in
                WorktreeHeaderView(
                    worktree: worktree,
                    optionKeyDown: optionKeyDown
                )
                .listRowInsets(EdgeInsets(top: 0, leading: baseLeading + 14, bottom: 0, trailing: 0))
                .selectionDisabled()

                ForEach(appState.sessionsForWorktree(
                    folderID: folder.id,
                    path: worktree.path
                ).map(\.id), id: \.self) { sessionID in
                    SessionRowView(sessionID: sessionID, onRemove: {
                        appState.removeSession(id: sessionID)
                    })
                    .id(sessionID)
                    .tag(sessionID)
                    .listRowInsets(EdgeInsets(top: 0, leading: baseLeading + 28, bottom: 0, trailing: 0))
                }
            }

            ForEach(appState.missingWorktreeSessionGroups(for: folder.id)) { group in
                MissingWorktreeHeaderView(group: group)
                    .listRowInsets(EdgeInsets(top: 0, leading: baseLeading + 14, bottom: 0, trailing: 0))
                    .selectionDisabled()

                ForEach(group.sessionIDs, id: \.self) { sessionID in
                    SessionRowView(sessionID: sessionID, onRemove: {
                        appState.removeSession(id: sessionID)
                    })
                    .id(sessionID)
                    .tag(sessionID)
                    .listRowInsets(EdgeInsets(top: 0, leading: baseLeading + 28, bottom: 0, trailing: 0))
                }
            }
        }
    }
}
