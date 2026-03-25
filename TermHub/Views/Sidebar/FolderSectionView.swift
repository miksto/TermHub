import SwiftUI

struct FolderSectionView: View {
    @Environment(AppState.self) private var appState
    let folder: ManagedFolder
    var optionKeyDown: Bool = false
    var onRequestRemoveFolder: () -> Void

    @State private var isExpanded = true

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


    private func aheadBehindText(_ status: GitStatus) -> String {
        var parts: [String] = []
        if status.ahead > 0 { parts.append("↑\(status.ahead)") }
        if status.behind > 0 { parts.append("↓\(status.behind)") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        // Read sessionListVersion to re-evaluate when sessions are added/removed.
        // The sessions array itself is @ObservationIgnored for isolation.
        let _ = appState.sessionListVersion
        Section(isExpanded: $isExpanded) {
            // Plain shell sessions
            ForEach(plainSessionIDs, id: \.self) { sessionID in
                SessionRowView(sessionID: sessionID, onRemove: {
                    appState.removeSession(id: sessionID)
                })
                .tag(sessionID)
                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 0))
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
                        SandboxButtonLabel("Branch", systemImage: "arrow.triangle.branch", showSandbox: optionKeyDown && !appState.sandboxes.isEmpty)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        if NSEvent.modifierFlags.contains(.option) {
                            appState.pendingNewBranchSandbox = appState.lastUsedSandboxName
                        }
                        appState.pendingNewBranchFolder = folder
                    } label: {
                        SandboxButtonLabel("New", systemImage: "plus", showSandbox: optionKeyDown && !appState.sandboxes.isEmpty)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 2)
            .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 0))
            .selectionDisabled()

            // Worktree groups
            ForEach(worktreeGroups) { group in
                WorktreeHeaderView(
                    folderID: folder.id,
                    worktreePath: group.worktreePath,
                    branchName: group.branchName,
                    optionKeyDown: optionKeyDown
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 0))
                .selectionDisabled()

                ForEach(group.sessionIDs, id: \.self) { sessionID in
                    SessionRowView(sessionID: sessionID, onRemove: {
                        appState.removeSession(id: sessionID)
                    })
                    .tag(sessionID)
                    .listRowInsets(EdgeInsets(top: 0, leading: 28, bottom: 0, trailing: 0))
                }
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
                if folder.isGitRepo, let status = appState.gitStatus(forFolderPath: folder.path) {
                    if let branch = status.currentBranch {
                        Text(branch)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if status.isDirty {
                        DiffStatsText(status: status)
                    }
                    if status.ahead > 0 || status.behind > 0 {
                        Text(aheadBehindText(status))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contextMenu {
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(folder.path, forType: .string)
                }
                Button("Remove Folder", role: .destructive) {
                    onRequestRemoveFolder()
                }
            }
            .selectionDisabled()
        }
    }
}

struct SandboxButtonLabel: View {
    let title: String
    let systemImage: String
    let showSandbox: Bool

    init(_ title: String, systemImage: String, showSandbox: Bool) {
        self.title = title
        self.systemImage = systemImage
        self.showSandbox = showSandbox
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .frame(width: 18)
            Text(title)
            if showSandbox {
                Image(systemName: "shippingbox")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}
