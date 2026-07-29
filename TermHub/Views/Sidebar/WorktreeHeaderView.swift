import SwiftUI

struct WorktreeHeaderView: View {
    @Environment(AppState.self) private var appState
    let worktree: GitWorktree
    var optionKeyDown: Bool = false
    @State private var showRemovalConfirmation = false

    private func aheadBehindText(_ status: GitStatus) -> String {
        var parts: [String] = []
        if status.ahead > 0 { parts.append("↑\(status.ahead)") }
        if status.behind > 0 { parts.append("↓\(status.behind)") }
        return parts.joined(separator: " ")
    }

    private var folder: ManagedFolder? {
        appState.folders.first(where: { $0.id == worktree.folderID })
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: worktree.isLocked ? "lock.fill" : "arrow.triangle.branch")
                .foregroundStyle(.secondary)
            Text(worktree.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            if worktree.isLocked, let reason = worktree.lockReason {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(reason)
            }
            if let status = appState.gitStatuses[worktree.path] {
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
            ShellSplitButton(
                folderID: worktree.folderID,
                folderName: folder?.name ?? "",
                cwd: worktree.path,
                worktreePath: worktree.path,
                branchName: worktree.branch,
                optionKeyDown: optionKeyDown
            )
        }
        .padding(.top, 6)
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(worktree.path, forType: .string)
            }
            if let branch = worktree.branch {
                Button("Copy Branch Name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(branch, forType: .string)
                }
            }
            Button("Refresh Worktrees") {
                appState.refreshWorktrees(folderIDs: [worktree.folderID])
            }
            Divider()
            Button("Remove Worktree…", role: .destructive) {
                showRemovalConfirmation = true
            }
            .disabled(worktree.isLocked || appState.worktreeRemovalInProgress.contains(worktree.id))
        }
        .confirmationDialog(
            "Remove \(worktree.displayName)?",
            isPresented: $showRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Worktree", role: .destructive) {
                appState.removeWorktree(folderID: worktree.folderID, path: worktree.path)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = appState.sessionsForWorktree(
                folderID: worktree.folderID,
                path: worktree.path
            ).count
            Text(
                "\(worktree.path)\n\n\(count) attached TermHub session(s) will close after Git successfully removes the worktree. The local branch will be kept."
            )
        }
    }
}

struct MissingWorktreeHeaderView: View {
    let group: MissingWorktreeSessionGroup

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Missing Worktree: \(group.displayName)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 6)
        .help(group.path)
        .contextMenu {
            Button("Copy Last-Known Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(group.path, forType: .string)
            }
            if let branch = group.branchName {
                Button("Copy Branch Name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(branch, forType: .string)
                }
            }
        }
    }
}
