import SwiftUI

struct WorktreeHeaderView: View {
    @Environment(AppState.self) private var appState
    let folderID: UUID
    let worktreePath: String
    let branchName: String
    var optionKeyDown: Bool = false

    private func aheadBehindText(_ status: GitStatus) -> String {
        var parts: [String] = []
        if status.ahead > 0 { parts.append("↑\(status.ahead)") }
        if status.behind > 0 { parts.append("↓\(status.behind)") }
        return parts.joined(separator: " ")
    }

    private var folder: ManagedFolder? {
        appState.folders.first(where: { $0.id == folderID })
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
            Text(branchName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            if let status = appState.gitStatuses[worktreePath] {
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
                folderID: folderID,
                folderName: folder?.name ?? "",
                cwd: worktreePath,
                worktreePath: worktreePath,
                branchName: branchName,
                optionKeyDown: optionKeyDown
            )
        }
        .padding(.top, 6)
    }
}
