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

    private var showSandboxIndicator: Bool {
        folder?.hasSandbox == true && optionKeyDown
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
                guard let folder else { return }
                let sandbox = folder.hasSandbox && NSEvent.modifierFlags.contains(.option)
                appState.addSession(
                    folderID: folderID,
                    title: "\(folder.name) [\(branchName)]",
                    cwd: worktreePath,
                    worktreePath: worktreePath,
                    branchName: branchName,
                    isSandboxSession: sandbox
                )
            } label: {
                SandboxButtonLabel(
                    "Shell",
                    systemImage: "terminal",
                    showSandbox: showSandboxIndicator
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.top, 6)
    }
}
