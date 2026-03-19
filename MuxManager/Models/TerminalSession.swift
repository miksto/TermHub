import Foundation

struct TerminalSession: Identifiable, Codable, Hashable {
    let id: UUID
    var folderID: UUID
    var title: String
    var workingDirectory: String
    var worktreePath: String?
    var branchName: String?
    var tmuxSessionName: String

    init(
        id: UUID = UUID(),
        folderID: UUID,
        title: String,
        workingDirectory: String,
        worktreePath: String? = nil,
        branchName: String? = nil,
        tmuxSessionName: String? = nil
    ) {
        self.id = id
        self.folderID = folderID
        self.title = title
        self.workingDirectory = workingDirectory
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.tmuxSessionName = tmuxSessionName ?? "mux-\(id.uuidString.prefix(8).lowercased())"
    }
}
