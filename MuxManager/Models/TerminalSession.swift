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
        self.tmuxSessionName = tmuxSessionName ?? Self.generateTmuxSessionName(
            workingDirectory: workingDirectory,
            branchName: branchName,
            id: id
        )
    }

    /// Generates a tmux session name following the convention:
    /// - Plain shell: `mux-<foldername>-<uuid4>` (first 4 chars of UUID for uniqueness)
    /// - Worktree: `mux-<foldername>-<branch>-<uuid4>` with slashes replaced by dashes
    static func generateTmuxSessionName(workingDirectory: String, branchName: String?, id: UUID = UUID()) -> String {
        let folderName = (workingDirectory as NSString).lastPathComponent
        let shortID = String(id.uuidString.prefix(4)).lowercased()
        if let branch = branchName {
            let sanitizedBranch = branch.replacingOccurrences(of: "/", with: "-")
            return "mux-\(folderName)-\(sanitizedBranch)-\(shortID)"
        }
        return "mux-\(folderName)-\(shortID)"
    }
}
