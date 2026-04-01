import Foundation

struct ManagedFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var sessionIDs: [UUID]
    var isGitRepo: Bool
    var isExpanded: Bool

    init(id: UUID = UUID(), name: String? = nil, path: String, sessionIDs: [UUID] = [], isGitRepo: Bool? = nil, isExpanded: Bool = true) {
        self.id = id
        self.name = name ?? (path as NSString).lastPathComponent
        self.path = path
        self.sessionIDs = sessionIDs
        self.isGitRepo = isGitRepo ?? GitService.isGitRepo(path: path)
        self.isExpanded = isExpanded
    }

    /// Whether the folder path still exists on disk.
    var pathExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        sessionIDs = try container.decode([UUID].self, forKey: .sessionIDs)
        isGitRepo = try container.decode(Bool.self, forKey: .isGitRepo)
        isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
    }
}
