import SwiftUI

struct FolderSectionView: View {
    @Environment(AppState.self) private var appState
    let folder: ManagedFolder
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
                Button {
                    if !folder.pathExists {
                        appState.errorMessage = "Cannot create session: folder path no longer exists at \(folder.path)"
                        return
                    }
                    appState.addSession(
                        folderID: folder.id,
                        title: "\(folder.name) – Shell",
                        cwd: folder.path
                    )
                } label: {
                    Label("Shell", systemImage: "terminal")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if folder.isGitRepo {
                    Button {
                        appState.pendingWorktreeFolder = folder
                    } label: {
                        Label("Branch", systemImage: "arrow.triangle.branch")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        appState.pendingNewBranchFolder = folder
                    } label: {
                        Label("New", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 2)
            .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 0))

            // Worktree groups
            ForEach(worktreeGroups) { group in
                WorktreeHeaderView(
                    folderID: folder.id,
                    worktreePath: group.worktreePath,
                    branchName: group.branchName
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 0))

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
                Button("Remove Folder", role: .destructive) {
                    onRequestRemoveFolder()
                }
            }
        }
    }
}
