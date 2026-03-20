import Foundation

struct ManagedFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var sessionIDs: [UUID]
    var isGitRepo: Bool

    init(id: UUID = UUID(), name: String? = nil, path: String, sessionIDs: [UUID] = [], isGitRepo: Bool? = nil) {
        self.id = id
        self.name = name ?? (path as NSString).lastPathComponent
        self.path = path
        self.sessionIDs = sessionIDs
        self.isGitRepo = isGitRepo ?? GitService.isGitRepo(path: path)
    }

    /// Whether the folder path still exists on disk.
    var pathExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    // Custom decoder for backward compatibility with saved state lacking isGitRepo
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        sessionIDs = try container.decode([UUID].self, forKey: .sessionIDs)
        isGitRepo = try container.decodeIfPresent(Bool.self, forKey: .isGitRepo)
            ?? GitService.isGitRepo(path: path)
    }
}
