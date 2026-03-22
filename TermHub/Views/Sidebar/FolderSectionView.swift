import SwiftUI

struct FolderSectionView: View {
    @Environment(AppState.self) private var appState
    let folder: ManagedFolder
    var onRequestRemoveFolder: () -> Void

    @State private var isExpanded = true

    private func diffText(_ status: GitStatus) -> String {
        var parts: [String] = []
        if status.linesAdded > 0 { parts.append("+\(status.linesAdded)") }
        if status.linesDeleted > 0 { parts.append("-\(status.linesDeleted)") }
        return parts.joined(separator: " ")
    }

    private func aheadBehindText(_ status: GitStatus) -> String {
        var parts: [String] = []
        if status.ahead > 0 { parts.append("↑\(status.ahead)") }
        if status.behind > 0 { parts.append("↓\(status.behind)") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        Section(isExpanded: $isExpanded) {
            ForEach(folder.sessionIDs, id: \.self) { sessionID in
                SessionRowView(sessionID: sessionID, onRemove: {
                    appState.removeSession(id: sessionID)
                })
                .tag(sessionID)
                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 0))
            }
            .onMove { from, to in
                appState.moveSession(fromOffsets: from, toOffset: to, inFolderID: folder.id)
            }

            // Action buttons row below sessions
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
            .moveDisabled(true)
            .padding(.top, 2)
            .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 0))
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
                    if status.isDirty {
                        Text(diffText(status))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
