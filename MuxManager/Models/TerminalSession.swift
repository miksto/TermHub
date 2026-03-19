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
            branchName: branchName
        )
    }

    /// Generates a tmux session name following the convention:
    /// - Plain shell: `mux-<foldername>`
    /// - Worktree: `mux-<foldername>-<branch>` with slashes replaced by dashes
    static func generateTmuxSessionName(workingDirectory: String, branchName: String?) -> String {
        let folderName = (workingDirectory as NSString).lastPathComponent
        if let branch = branchName {
            let sanitizedBranch = branch.replacingOccurrences(of: "/", with: "-")
            return "mux-\(folderName)-\(sanitizedBranch)"
        }
        return "mux-\(folderName)"
    }
}
