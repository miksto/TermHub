import SwiftUI

struct GroupHeaderRow: View {
    @Environment(AppState.self) private var appState
    let group: FolderGroup
    var onRequestRemoveGroup: () -> Void
    @Binding var draggedSidebarItem: SidebarItem?
    @Binding var dropTargetSidebarItem: SidebarItem?
    @State private var isRenaming = false
    @State private var renameText = ""

    private var isDragSource: Bool {
        draggedSidebarItem == .group(group.id)
    }

    private var isDropTarget: Bool {
        dropTargetSidebarItem == .group(group.id) && draggedSidebarItem != nil && draggedSidebarItem != .group(group.id)
    }

    private var isReceivingFolder: Bool {
        if case .folder = draggedSidebarItem {
            return isDropTarget
        }
        return false
    }

    private var isReorderTarget: Bool {
        if case .group = draggedSidebarItem {
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
                    .rotationEffect(.degrees(group.isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: group.isExpanded)

                if isRenaming {
                    TextField("Group Name", text: $renameText, onCommit: {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            appState.renameGroup(id: group.id, name: trimmed)
                        }
                        isRenaming = false
                    })
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .onExitCommand { isRenaming = false }
                } else {
                    Label(group.name, systemImage: "folder.fill.badge.gearshape")
                        .font(.headline)
                }

                Text("\(group.folderIDs.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())

                Spacer()
            }
            .opacity(isDragSource ? 0.4 : 1.0)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isReceivingFolder ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.setGroupExpanded(id: group.id, isExpanded: !group.isExpanded)
        }
        .onDrag {
            draggedSidebarItem = .group(group.id)
            return NSItemProvider(object: "group:\(group.id.uuidString)" as NSString)
        } preview: {
            GroupDragPreview(name: group.name)
        }
        .onDrop(of: [.text], delegate: GroupDropDelegate(
            targetGroupID: group.id,
            appState: appState,
            draggedSidebarItem: $draggedSidebarItem,
            dropTargetSidebarItem: $dropTargetSidebarItem
        ))
        .contextMenu {
            Button("Rename Group") {
                renameText = group.name
                isRenaming = true
            }
            Divider()
            Button("Remove Group", role: .destructive) {
                onRequestRemoveGroup()
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

private struct GroupDragPreview: View {
    let name: String

    var body: some View {
        Label(name, systemImage: "folder.fill.badge.gearshape")
            .font(.headline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct GroupDropDelegate: DropDelegate {
    let targetGroupID: UUID
    let appState: AppState
    @Binding var draggedSidebarItem: SidebarItem?
    @Binding var dropTargetSidebarItem: SidebarItem?

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragged = draggedSidebarItem else { return false }
        switch dragged {
        case .folder:
            // Folders can be dropped onto groups
            return true
        case .group(let id):
            return id != targetGroupID
        }
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedSidebarItem else { return }
        switch dragged {
        case .folder:
            withAnimation(.easeInOut(duration: 0.15)) {
                dropTargetSidebarItem = .group(targetGroupID)
            }
        case .group(let id) where id != targetGroupID:
            withAnimation(.easeInOut(duration: 0.15)) {
                dropTargetSidebarItem = .group(targetGroupID)
            }
        default:
            break
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if dropTargetSidebarItem == .group(targetGroupID) {
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
        guard let dragged = draggedSidebarItem else { return false }
        switch dragged {
        case .folder(let folderID):
            appState.moveFolderToGroup(folderID: folderID, groupID: targetGroupID)
            return true
        case .group(let draggedGroupID):
            guard draggedGroupID != targetGroupID,
                  let fromIndex = appState.sidebarOrder.firstIndex(of: .group(draggedGroupID)),
                  let toIndex = appState.sidebarOrder.firstIndex(of: .group(targetGroupID))
            else { return false }
            appState.moveSidebarItem(from: fromIndex, to: toIndex)
            return true
        }
    }
}
