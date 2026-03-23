import SwiftUI

struct WorktreeHeaderView: View {
    @Environment(AppState.self) private var appState
    let folderID: UUID
    let worktreePath: String
    let branchName: String

    private func aheadBehindText(_ status: GitStatus) -> String {
        var parts: [String] = []
        if status.ahead > 0 { parts.append("↑\(status.ahead)") }
        if status.behind > 0 { parts.append("↓\(status.behind)") }
        return parts.joined(separator: " ")
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
            Button {
                guard let folder = appState.folders.first(where: { $0.id == folderID }) else { return }
                appState.addSession(
                    folderID: folderID,
                    title: "\(folder.name) [\(branchName)]",
                    cwd: worktreePath,
                    worktreePath: worktreePath,
                    branchName: branchName
                )
            } label: {
                Label("Shell", systemImage: "terminal")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.top, 6)
    }
}
