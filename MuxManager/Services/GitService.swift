import Foundation

enum GitServiceError: Error, LocalizedError {
    case commandFailed(String)
    case notAGitRepo

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Git command failed: \(message)"
        case .notAGitRepo:
            return "Not a git repository"
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
            throw GitServiceError.commandFailed(errorOutput.isEmpty ? output : errorOutput)
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

    static func addWorktree(repoPath: String, branch: String) throws -> String {
        let sanitized = branch.replacingOccurrences(of: "/", with: "-")
        let repoName = (repoPath as NSString).lastPathComponent
        let parentDir = (repoPath as NSString).deletingLastPathComponent
        let worktreePath = (parentDir as NSString).appendingPathComponent("\(repoName)-\(sanitized)")

        try run(["-C", repoPath, "worktree", "add", worktreePath, branch])
        return worktreePath
    }

    static func addWorktreeNewBranch(repoPath: String, newBranch: String) throws -> String {
        let sanitized = newBranch.replacingOccurrences(of: "/", with: "-")
        let repoName = (repoPath as NSString).lastPathComponent
        let parentDir = (repoPath as NSString).deletingLastPathComponent
        let worktreePath = (parentDir as NSString).appendingPathComponent("\(repoName)-\(sanitized)")

        try run(["-C", repoPath, "worktree", "add", "-b", newBranch, worktreePath])
        return worktreePath
    }

    static func removeWorktree(repoPath: String, worktreePath: String) throws {
        try run(["-C", repoPath, "worktree", "remove", worktreePath])
    }
}
