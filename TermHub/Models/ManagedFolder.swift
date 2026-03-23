import Foundation

struct ManagedFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var sessionIDs: [UUID]
    var isGitRepo: Bool
    var sandboxName: String?

    var hasSandbox: Bool { sandboxName != nil }

    init(id: UUID = UUID(), name: String? = nil, path: String, sessionIDs: [UUID] = [], isGitRepo: Bool? = nil, sandboxName: String? = nil) {
        self.id = id
        self.name = name ?? (path as NSString).lastPathComponent
        self.path = path
        self.sessionIDs = sessionIDs
        self.isGitRepo = isGitRepo ?? GitService.isGitRepo(path: path)
        self.sandboxName = sandboxName
    }

    /// Whether the folder path still exists on disk.
    var pathExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
