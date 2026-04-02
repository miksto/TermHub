import SwiftUI

struct FolderHeaderRow: View {
    @Environment(AppState.self) private var appState
    let folder: ManagedFolder
    var optionKeyDown: Bool = false
    var onRequestRemoveFolder: () -> Void
    @Binding var draggedSidebarItem: SidebarItem?
    @Binding var dropTargetSidebarItem: SidebarItem?
    var isInsideGroup: Bool = false

    private func aheadBehindText(_ status: GitStatus) -> String {
        var parts: [String] = []
        if status.ahead > 0 { parts.append("↑\(status.ahead)") }
        if status.behind > 0 { parts.append("↓\(status.behind)") }
        return parts.joined(separator: " ")
    }

    private var isDragSource: Bool {
        draggedSidebarItem == .folder(folder.id)
    }

    private var isDropTarget: Bool {
        dropTargetSidebarItem == .folder(folder.id)
            && draggedSidebarItem != nil
            && draggedSidebarItem != .folder(folder.id)
    }

    private var isReorderTarget: Bool {
        // Only show reorder indicator for folder-to-folder reordering at the same level
        if case .folder = draggedSidebarItem {
            return isDropTarget
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            if isReorderTarget {
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
            draggedSidebarItem = .folder(folder.id)
            return NSItemProvider(object: "folder:\(folder.id.uuidString)" as NSString)
        } preview: {
            FolderDragPreview(name: folder.name)
        }
        .onDrop(of: [.text], delegate: FolderDropDelegate(
            targetFolderID: folder.id,
            appState: appState,
            draggedSidebarItem: $draggedSidebarItem,
            dropTargetSidebarItem: $dropTargetSidebarItem,
            isInsideGroup: isInsideGroup
        ))
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(folder.path, forType: .string)
            }
            if isInsideGroup {
                Button("Remove from Group") {
                    appState.moveFolderOutOfGroup(folderID: folder.id)
                }
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
    @Binding var draggedSidebarItem: SidebarItem?
    @Binding var dropTargetSidebarItem: SidebarItem?
    var isInsideGroup: Bool = false

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragged = draggedSidebarItem else { return false }
        if case .folder(let id) = dragged {
            return id != targetFolderID
        }
        return false
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedSidebarItem else { return }
        if case .folder(let id) = dragged, id != targetFolderID {
            withAnimation(.easeInOut(duration: 0.15)) {
                dropTargetSidebarItem = .folder(targetFolderID)
            }
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if dropTargetSidebarItem == .folder(targetFolderID) {
                dropTargetSidebarItem = nil
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedSidebarItem = nil
            dropTargetSidebarItem = nil
        }
        guard case .folder(let draggedFolderID) = draggedSidebarItem,
              draggedFolderID != targetFolderID else { return false }

        // Determine if both folders are in the same context (same group or both ungrouped)
        let draggedGroup = appState.group(forFolderID: draggedFolderID)
        let targetGroup = appState.group(forFolderID: targetFolderID)

        if let tg = targetGroup, draggedGroup?.id == tg.id {
            // Both in the same group — reorder within group
            guard let fromIndex = tg.folderIDs.firstIndex(of: draggedFolderID),
                  let toIndex = tg.folderIDs.firstIndex(of: targetFolderID) else { return false }
            appState.moveFolderWithinGroup(groupID: tg.id, from: fromIndex, to: toIndex)
            return true
        } else if targetGroup == nil && draggedGroup == nil {
            // Both ungrouped — reorder in sidebarOrder
            guard let fromIndex = appState.sidebarOrder.firstIndex(of: .folder(draggedFolderID)),
                  let toIndex = appState.sidebarOrder.firstIndex(of: .folder(targetFolderID))
            else { return false }
            appState.moveSidebarItem(from: fromIndex, to: toIndex)
            return true
        } else if let tg = targetGroup {
            // Dragged folder is moving into target's group
            appState.moveFolderToGroup(folderID: draggedFolderID, groupID: tg.id)
            return true
        } else {
            // Target is ungrouped — move dragged folder out of its group
            if let toIndex = appState.sidebarOrder.firstIndex(of: .folder(targetFolderID)) {
                appState.moveFolderOutOfGroup(folderID: draggedFolderID, atSidebarIndex: toIndex)
            } else {
                appState.moveFolderOutOfGroup(folderID: draggedFolderID)
            }
            return true
        }
    }
}
