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

    /// Returns the container directory for all worktrees belonging to a repo.
    static func worktreeContainerPath(repoPath: String) -> String {
        let repoName = (repoPath as NSString).lastPathComponent
        let parentDir = (repoPath as NSString).deletingLastPathComponent
        return (parentDir as NSString).appendingPathComponent("\(repoName)-termhub")
    }

    /// Computes the worktree path for a given repo path and branch name.
    static func worktreePath(repoPath: String, branch: String) -> String {
        let sanitized = sanitizeBranchName(branch)
        let container = worktreeContainerPath(repoPath: repoPath)
        return (container as NSString).appendingPathComponent(sanitized)
    }

    /// Ensures the shared worktree container directory exists.
    private static func ensureWorktreeContainer(repoPath: String) throws {
        let container = worktreeContainerPath(repoPath: repoPath)
        try FileManager.default.createDirectory(
            atPath: container,
            withIntermediateDirectories: true
        )
    }

    static func addWorktree(repoPath: String, branch: String) throws -> String {
        let path = worktreePath(repoPath: repoPath, branch: branch)
        try ensureWorktreeContainer(repoPath: repoPath)
        try run(["-C", repoPath, "worktree", "add", path, branch])
        return path
    }

    static func addWorktreeNewBranch(repoPath: String, newBranch: String) throws -> String {
        let path = worktreePath(repoPath: repoPath, branch: newBranch)
        try ensureWorktreeContainer(repoPath: repoPath)
        try run(["-C", repoPath, "worktree", "add", "-b", newBranch, path])
        return path
    }

    static func removeWorktree(repoPath: String, worktreePath: String) throws {
        try run(["-C", repoPath, "worktree", "remove", "--force", worktreePath])
    }

    /// Returns (linesAdded, linesDeleted) for uncommitted changes (staged + unstaged).
    static func diffStats(path: String) -> (added: Int, deleted: Int) {
        do {
            let output = try run(["-C", path, "diff", "--numstat", "HEAD"])
            var added = 0
            var deleted = 0
            for line in output.components(separatedBy: "\n") where !line.isEmpty {
                let parts = line.split(separator: "\t")
                guard parts.count >= 2 else { continue }
                // Binary files show "-" instead of numbers
                added += Int(parts[0]) ?? 0
                deleted += Int(parts[1]) ?? 0
            }
            return (added, deleted)
        } catch {
            return (0, 0)
        }
    }

    static func aheadBehind(path: String) -> (ahead: Int, behind: Int) {
        do {
            let output = try run(["-C", path, "rev-list", "--left-right", "--count", "HEAD...@{u}"])
            let parts = output.split(separator: "\t")
            guard parts.count == 2,
                  let ahead = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let behind = Int(parts[1].trimmingCharacters(in: .whitespaces))
            else {
                return (0, 0)
            }
            return (ahead, behind)
        } catch {
            return (0, 0)
        }
    }

    static func status(path: String) -> GitStatus {
        let (added, deleted) = diffStats(path: path)
        let (ahead, behind) = aheadBehind(path: path)
        return GitStatus(linesAdded: added, linesDeleted: deleted, ahead: ahead, behind: behind)
    }

    /// Returns the raw unified diff output for uncommitted changes (staged + unstaged) vs HEAD.
    static func diff(path: String) -> String {
        do {
            return try run(["-C", path, "diff", "HEAD"])
        } catch {
            return ""
        }
    }

    /// Parses raw unified diff output into structured `GitDiff`.
    static func parseDiff(_ raw: String) -> GitDiff {
        guard !raw.isEmpty else { return .empty }

        var files: [DiffFile] = []
        // Split on "diff --git" boundaries, dropping the empty first element
        let fileSections = raw.components(separatedBy: "diff --git ")
            .dropFirst()
            .map { "diff --git " + $0 }

        for section in fileSections {
            let lines = section.components(separatedBy: "\n")

            // Extract paths from --- and +++ lines
            var oldPath = ""
            var newPath = ""
            var isBinary = false
            var hunkStartIndex = 0

            for (index, line) in lines.enumerated() {
                if line.hasPrefix("--- a/") {
                    oldPath = String(line.dropFirst(6))
                } else if line.hasPrefix("--- /dev/null") {
                    oldPath = "/dev/null"
                } else if line.hasPrefix("+++ b/") {
                    newPath = String(line.dropFirst(6))
                } else if line.hasPrefix("+++ /dev/null") {
                    newPath = "/dev/null"
                } else if line.hasPrefix("Binary files") {
                    isBinary = true
                } else if line.hasPrefix("@@") {
                    hunkStartIndex = index
                    break
                }
            }

            // If no paths found, try to extract from the diff --git line
            if oldPath.isEmpty, newPath.isEmpty, let firstLine = lines.first {
                let parts = firstLine.components(separatedBy: " ")
                if parts.count >= 4 {
                    oldPath = String(parts[2].dropFirst(2)) // drop "a/"
                    newPath = String(parts[3].dropFirst(2)) // drop "b/"
                }
            }

            // Parse hunks
            var hunks: [DiffHunk] = []
            if !isBinary {
                var currentHunkLines: [DiffLine] = []
                var currentHeader = ""
                var oldStart = 0
                var newStart = 0
                var oldLineNum = 0
                var newLineNum = 0
                var inHunk = false

                for lineIndex in hunkStartIndex..<lines.count {
                    let line = lines[lineIndex]

                    if line.hasPrefix("@@") {
                        // Save previous hunk
                        if inHunk {
                            hunks.append(DiffHunk(
                                header: currentHeader,
                                oldStart: oldStart,
                                newStart: newStart,
                                lines: currentHunkLines
                            ))
                        }

                        // Parse hunk header: @@ -oldStart,oldCount +newStart,newCount @@
                        currentHeader = line
                        currentHunkLines = []
                        inHunk = true

                        let headerContent = line.drop(while: { $0 == "@" || $0 == " " })
                        let ranges = headerContent.prefix(while: { $0 != "@" })
                        let rangeParts = ranges.split(separator: " ")
                        if rangeParts.count >= 2 {
                            let oldRange = rangeParts[0].dropFirst() // drop "-"
                            let newRange = rangeParts[1].dropFirst() // drop "+"
                            oldStart = Int(oldRange.split(separator: ",").first ?? "0") ?? 0
                            newStart = Int(newRange.split(separator: ",").first ?? "0") ?? 0
                        }
                        oldLineNum = oldStart
                        newLineNum = newStart
                    } else if inHunk {
                        if line.hasPrefix("\\") {
                            // "\ No newline at end of file" — skip
                            continue
                        }

                        let type: DiffLineType
                        let content: String
                        let oldNum: Int?
                        let newNum: Int?

                        if line.hasPrefix("+") {
                            type = .added
                            content = String(line.dropFirst())
                            oldNum = nil
                            newNum = newLineNum
                            newLineNum += 1
                        } else if line.hasPrefix("-") {
                            type = .removed
                            content = String(line.dropFirst())
                            oldNum = oldLineNum
                            newNum = nil
                            oldLineNum += 1
                        } else {
                            type = .context
                            content = line.isEmpty ? "" : String(line.dropFirst()) // drop leading space
                            oldNum = oldLineNum
                            newNum = newLineNum
                            oldLineNum += 1
                            newLineNum += 1
                        }

                        currentHunkLines.append(DiffLine(
                            type: type,
                            content: content,
                            oldLineNumber: oldNum,
                            newLineNumber: newNum
                        ))
                    }
                }

                // Save last hunk
                if inHunk {
                    hunks.append(DiffHunk(
                        header: currentHeader,
                        oldStart: oldStart,
                        newStart: newStart,
                        lines: currentHunkLines
                    ))
                }
            }

            files.append(DiffFile(
                oldPath: oldPath,
                newPath: newPath,
                isBinary: isBinary,
                hunks: hunks
            ))
        }

        return GitDiff(files: files)
    }
}
