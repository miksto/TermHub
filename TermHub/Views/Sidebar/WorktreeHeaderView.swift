import SwiftUI

struct WorktreeHeaderView: View {
    @Environment(AppState.self) private var appState
    let folderID: UUID
    let worktreePath: String
    let branchName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
            Text(branchName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            if let status = appState.gitStatuses[worktreePath], status.isDirty {
                DiffStatsText(status: status)
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
