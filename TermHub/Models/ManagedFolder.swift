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
}
