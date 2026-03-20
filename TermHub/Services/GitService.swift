import Foundation

enum GitServiceError: Error, LocalizedError {
    case commandFailed(String)
    case notAGitRepo
    case worktreeAlreadyExists

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Git command failed: \(message)"
        case .notAGitRepo:
            return "Not a git repository"
        case .worktreeAlreadyExists:
            return "A worktree or branch with this name already exists"
        }
    }
}

enum GitService {
    @discardableResult
    private static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.environment = ShellEnvironment.shellEnvironment

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if process.terminationStatus != 0 {
            let message = errorOutput.isEmpty ? output : errorOutput
            if message.contains("already exists") {
                throw GitServiceError.worktreeAlreadyExists
            }
            throw GitServiceError.commandFailed(message)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isGitRepo(path: String) -> Bool {
        do {
            try run(["-C", path, "rev-parse", "--git-dir"])
            return true
        } catch {
            return false
        }
    }

    static func listBranches(repoPath: String) throws -> [String] {
        let output = try run(["-C", repoPath, "branch", "--format=%(refname:short)"])
        guard !output.isEmpty else { return [] }
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    /// Sanitizes a branch name by replacing slashes with dashes for use in file paths.
    static func sanitizeBranchName(_ branch: String) -> String {
        branch.replacingOccurrences(of: "/", with: "-")
    }

    /// Computes the worktree path for a given repo path and branch name.
    static func worktreePath(repoPath: String, branch: String) -> String {
        let sanitized = sanitizeBranchName(branch)
        let repoName = (repoPath as NSString).lastPathComponent
        let parentDir = (repoPath as NSString).deletingLastPathComponent
        return (parentDir as NSString).appendingPathComponent("\(repoName)-\(sanitized)")
    }

    static func addWorktree(repoPath: String, branch: String) throws -> String {
        let path = worktreePath(repoPath: repoPath, branch: branch)
        try run(["-C", repoPath, "worktree", "add", path, branch])
        return path
    }

    static func addWorktreeNewBranch(repoPath: String, newBranch: String) throws -> String {
        let path = worktreePath(repoPath: repoPath, branch: newBranch)
        try run(["-C", repoPath, "worktree", "add", "-b", newBranch, path])
        return path
    }

    static func removeWorktree(repoPath: String, worktreePath: String) throws {
        try run(["-C", repoPath, "worktree", "remove", "--force", worktreePath])
    }
}
