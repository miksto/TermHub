import Foundation

/// Represents an organizational group of folders in the sidebar.
struct FolderGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var folderIDs: [UUID]
    var isExpanded: Bool

    init(id: UUID = UUID(), name: String, folderIDs: [UUID] = [], isExpanded: Bool = true) {
        self.id = id
        self.name = name
        self.folderIDs = folderIDs
        self.isExpanded = isExpanded
    }
}

/// A top-level sidebar item: either an ungrouped folder or a folder group.
enum SidebarItem: Codable, Equatable, Hashable {
    case folder(UUID)
    case group(UUID)
}
