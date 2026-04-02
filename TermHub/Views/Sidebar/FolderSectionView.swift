import SwiftUI

struct FolderSectionView: View {
    @Environment(AppState.self) private var appState
    let folder: ManagedFolder
    var optionKeyDown: Bool = false
    var onRequestRemoveFolder: () -> Void
    @Binding var draggedSidebarItem: SidebarItem?
    @Binding var dropTargetSidebarItem: SidebarItem?
    var isInsideGroup: Bool = false

    private struct WorktreeGroup: Identifiable {
        let worktreePath: String
        let branchName: String
        let sessionIDs: [UUID]
        var id: String { worktreePath }
    }

    private var plainSessionIDs: [UUID] {
        folder.sessionIDs.filter { id in
            appState.sessions.first(where: { $0.id == id })?.worktreePath == nil
        }
    }

    private var worktreeGroups: [WorktreeGroup] {
        var seen: [String: Int] = [:]
        var groups: [WorktreeGroup] = []
        for sessionID in folder.sessionIDs {
            guard let session = appState.sessions.first(where: { $0.id == sessionID }),
                  let wt = session.worktreePath else { continue }
            if let idx = seen[wt] {
                groups[idx] = WorktreeGroup(
                    worktreePath: groups[idx].worktreePath,
                    branchName: groups[idx].branchName,
                    sessionIDs: groups[idx].sessionIDs + [sessionID]
                )
            } else {
                seen[wt] = groups.count
                groups.append(WorktreeGroup(
                    worktreePath: wt,
                    branchName: session.branchName ?? "worktree",
                    sessionIDs: [sessionID]
                ))
            }
        }
        return groups
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
            isInsideGroup: isInsideGroup
        )
        .selectionDisabled()
        .listRowInsets(EdgeInsets(top: 4, leading: baseLeading, bottom: 2, trailing: 0))

        if folder.isExpanded {
            // Plain shell sessions
            ForEach(plainSessionIDs, id: \.self) { sessionID in
                SessionRowView(sessionID: sessionID, onRemove: {
                    appState.removeSession(id: sessionID)
                })
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
                }
            }
            .padding(.top, 2)
            .listRowInsets(EdgeInsets(top: 0, leading: baseLeading + 14, bottom: 0, trailing: 0))
            .selectionDisabled()

            // Worktree groups
            ForEach(worktreeGroups) { group in
                WorktreeHeaderView(
                    folderID: folder.id,
                    worktreePath: group.worktreePath,
                    branchName: group.branchName,
                    optionKeyDown: optionKeyDown
                )
                .listRowInsets(EdgeInsets(top: 0, leading: baseLeading + 14, bottom: 0, trailing: 0))
                .selectionDisabled()

                ForEach(group.sessionIDs, id: \.self) { sessionID in
                    SessionRowView(sessionID: sessionID, onRemove: {
                        appState.removeSession(id: sessionID)
                    })
                    .tag(sessionID)
                    .listRowInsets(EdgeInsets(top: 0, leading: baseLeading + 28, bottom: 0, trailing: 0))
                }
            }
        }
    }
}
