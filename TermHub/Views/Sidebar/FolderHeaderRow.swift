import SwiftUI

struct FolderHeaderRow: View {
    @Environment(AppState.self) private var appState
    let folder: ManagedFolder
    var optionKeyDown: Bool = false
    var onRequestRemoveFolder: () -> Void
    @Binding var draggedFolderID: UUID?
    @Binding var dropTargetFolderID: UUID?

    private func aheadBehindText(_ status: GitStatus) -> String {
        var parts: [String] = []
        if status.ahead > 0 { parts.append("↑\(status.ahead)") }
        if status.behind > 0 { parts.append("↓\(status.behind)") }
        return parts.joined(separator: " ")
    }

    private var isDragSource: Bool {
        draggedFolderID == folder.id
    }

    private var isDropTarget: Bool {
        dropTargetFolderID == folder.id && draggedFolderID != nil && draggedFolderID != folder.id
    }

    var body: some View {
        VStack(spacing: 0) {
            if isDropTarget {
                dropIndicatorLine
            }

            HStack {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(folder.isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: folder.isExpanded)

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
            .opacity(isDragSource ? 0.4 : 1.0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.setFolderExpanded(id: folder.id, isExpanded: !folder.isExpanded)
        }
        .onDrag {
            draggedFolderID = folder.id
            return NSItemProvider(object: folder.id.uuidString as NSString)
        } preview: {
            FolderDragPreview(name: folder.name)
        }
        .onDrop(of: [.text], delegate: FolderDropDelegate(
            targetFolderID: folder.id,
            appState: appState,
            draggedFolderID: $draggedFolderID,
            dropTargetFolderID: $dropTargetFolderID
        ))
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(folder.path, forType: .string)
            }
            Button("Remove Folder", role: .destructive) {
                onRequestRemoveFolder()
            }
        }
    }

    private var dropIndicatorLine: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }
}

private struct FolderDragPreview: View {
    let name: String

    var body: some View {
        Label(name, systemImage: "folder")
            .font(.headline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct FolderDropDelegate: DropDelegate {
    let targetFolderID: UUID
    let appState: AppState
    @Binding var draggedFolderID: UUID?
    @Binding var dropTargetFolderID: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        draggedFolderID != nil && draggedFolderID != targetFolderID
    }

    func dropEntered(info: DropInfo) {
        guard draggedFolderID != nil, draggedFolderID != targetFolderID else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            dropTargetFolderID = targetFolderID
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if dropTargetFolderID == targetFolderID {
                dropTargetFolderID = nil
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedFolderID = nil
            dropTargetFolderID = nil
        }
        guard let draggedID = draggedFolderID,
              draggedID != targetFolderID,
              let fromIndex = appState.folders.firstIndex(where: { $0.id == draggedID }),
              let toIndex = appState.folders.firstIndex(where: { $0.id == targetFolderID })
        else { return false }
        appState.moveFolder(from: fromIndex, to: toIndex)
        return true
    }
}
