import Foundation

struct TerminalSession: Identifiable, Codable, Hashable {
    let id: UUID
    var folderID: UUID
    var title: String
    var workingDirectory: String
    var worktreePath: String?
    var branchName: String?
    var hasCustomTitle: Bool
    var isExternalWorktree: Bool
    var ownsBranch: Bool
    var tmuxSessionName: String

    init(
        id: UUID = UUID(),
        folderID: UUID,
        title: String,
        workingDirectory: String,
        worktreePath: String? = nil,
        branchName: String? = nil,
        hasCustomTitle: Bool = false,
        isExternalWorktree: Bool = false,
        ownsBranch: Bool = false,
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
        self.isExternalWorktree = isExternalWorktree
        self.ownsBranch = ownsBranch
        self.tmuxSessionName = tmuxSessionName ?? Self.generateTmuxSessionName(
            folderName: folderName ?? (workingDirectory as NSString).lastPathComponent,
            branchName: branchName,
            id: id
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        folderID = try container.decode(UUID.self, forKey: .folderID)
        title = try container.decode(String.self, forKey: .title)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath)
        branchName = try container.decodeIfPresent(String.self, forKey: .branchName)
        hasCustomTitle = try container.decodeIfPresent(Bool.self, forKey: .hasCustomTitle) ?? false
        isExternalWorktree = try container.decodeIfPresent(Bool.self, forKey: .isExternalWorktree) ?? false
        ownsBranch = try container.decodeIfPresent(Bool.self, forKey: .ownsBranch) ?? false
        tmuxSessionName = try container.decode(String.self, forKey: .tmuxSessionName)
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
