import Foundation

struct TerminalSession: Identifiable, Codable, Hashable {
    let id: UUID
    var folderID: UUID
    var title: String
    var workingDirectory: String
    var worktreePath: String?
    var branchName: String?
    var hasCustomTitle: Bool
    var tmuxSessionName: String

    init(
        id: UUID = UUID(),
        folderID: UUID,
        title: String,
        workingDirectory: String,
        worktreePath: String? = nil,
        branchName: String? = nil,
        hasCustomTitle: Bool = false,
        tmuxSessionName: String? = nil,
        folderName: String? = nil
    ) {
        self.id = id
        self.folderID = folderID
        self.title = title
        self.workingDirectory = workingDirectory
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.hasCustomTitle = hasCustomTitle
        self.tmuxSessionName = tmuxSessionName ?? Self.generateTmuxSessionName(
            folderName: folderName ?? (workingDirectory as NSString).lastPathComponent,
            branchName: branchName,
            id: id
        )
    }

    /// Generates a tmux session name following the convention:
    /// - Plain shell: `mux-<foldername>-<uuid4>` (first 4 chars of UUID for uniqueness)
    /// - Worktree: `mux-<foldername>-<branch>-<uuid4>` with slashes replaced by dashes
    static func generateTmuxSessionName(folderName: String, branchName: String?, id: UUID = UUID()) -> String {
        let shortID = String(id.uuidString.prefix(4)).lowercased()
        let sanitizedFolder = folderName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        if let branch = branchName {
            let sanitizedBranch = branch
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ".", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            return "mux-\(sanitizedFolder)-\(sanitizedBranch)-\(shortID)"
        }
        return "mux-\(sanitizedFolder)-\(shortID)"
    }
}
