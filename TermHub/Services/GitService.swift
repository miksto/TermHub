import Foundation

// All methods in GitService are synchronous and perform blocking I/O
// (Process + waitUntilExit). They must NEVER be called from the main thread.
// Use Task.detached {} when calling from @MainActor contexts.

enum GitServiceError: Error, LocalizedError, Equatable {
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

enum GitAction: String, CaseIterable, Sendable {
    case pull
    case push
    case fetch
    case stash
    case stashPop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pull: "Git Pull"
        case .push: "Git Push"
        case .fetch: "Git Fetch"
        case .stash: "Git Stash"
        case .stashPop: "Git Stash Pop"
        }
    }

    var icon: String {
        switch self {
        case .pull: "arrow.down.circle"
        case .push: "arrow.up.circle"
        case .fetch: "arrow.triangle.2.circlepath"
        case .stash: "archivebox"
        case .stashPop: "archivebox.fill"
        }
    }

    /// Returns the exact git command that will be run for the given path.
    func command(path: String) -> String {
        switch self {
        case .pull: return "git pull"
        case .push: return GitService.pushCommand(path: path)
        case .fetch: return "git fetch"
        case .stash: return "git stash"
        case .stashPop: return "git stash pop"
        }
    }

    func execute(path: String) throws {
        switch self {
        case .pull: try GitService.pull(path: path)
        case .push: try GitService.push(path: path)
        case .fetch: try GitService.fetch(path: path)
        case .stash: try GitService.stash(path: path)
        case .stashPop: try GitService.stashPop(path: path)
        }
    }
}

enum GitService {
    nonisolated(unsafe) static var commandRunner: CommandRunner = ProcessCommandRunner()

    @discardableResult
    private static func run(_ arguments: [String]) throws -> String {
        let result = commandRunner.run(
            executablePath: "/usr/bin/git",
            arguments: arguments,
            environment: ShellEnvironment.shellEnvironment
        )

        if result.exitCode != 0 {
            let message = result.errorOutput.isEmpty ? result.output : result.errorOutput
            if message.contains("already exists") {
                throw GitServiceError.worktreeAlreadyExists
            }
            throw GitServiceError.commandFailed(message)
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
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

    static func currentBranch(repoPath: String) -> String? {
        guard let output = try? run(["-C", repoPath, "symbolic-ref", "--short", "HEAD"]),
              !output.isEmpty else {
            return nil
        }
        return output
    }

    static func listBranchesWithDates(repoPath: String) throws -> [(branch: String, date: Date)] {
        let output = try run([
            "-C", repoPath,
            "for-each-ref",
            "--sort=-committerdate",
            "--format=%(refname:short)\t%(committerdate:iso8601)",
            "refs/heads/",
        ])
        guard !output.isEmpty else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return output.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2,
                  let date = formatter.date(from: String(parts[1]))
            else { return nil }
            return (branch: String(parts[0]), date: date)
        }
    }

    /// Returns branches with dates and the current branch name in a single git call.
    static func listBranchesWithDatesAndCurrent(repoPath: String) throws -> (branches: [(branch: String, date: Date)], currentBranch: String?) {
        let output = try run([
            "-C", repoPath,
            "for-each-ref",
            "--sort=-committerdate",
            "--format=%(refname:short)\t%(committerdate:iso8601)\t%(HEAD)",
            "refs/heads/",
        ])
        guard !output.isEmpty else { return ([], nil) }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var currentBranch: String?
        var branches: [(branch: String, date: Date)] = []

        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count >= 2,
                  let date = formatter.date(from: String(parts[1]))
            else { continue }
            let name = String(parts[0])
            branches.append((branch: name, date: date))
            if parts.count >= 3, parts[2] == "*" {
                currentBranch = name
            }
        }

        return (branches, currentBranch)
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

    static func addWorktreeNewBranch(repoPath: String, newBranch: String, startPoint: String? = nil) throws -> String {
        let path = worktreePath(repoPath: repoPath, branch: newBranch)
        try ensureWorktreeContainer(repoPath: repoPath)
        var args = ["-C", repoPath, "worktree", "add", "-b", newBranch, path]
        if let startPoint {
            args.append(startPoint)
        }
        try run(args)
        return path
    }

    /// Copies `.claude/settings.local.json` from the source repo into the worktree directory.
    /// Best-effort: silently does nothing if the source file doesn't exist or the copy fails.
    static func copyClaudeLocalSettings(from repoPath: String, to worktreePath: String) {
        let fm = FileManager.default
        let source = (repoPath as NSString).appendingPathComponent(".claude/settings.local.json")
        guard fm.fileExists(atPath: source) else { return }
        let destDir = (worktreePath as NSString).appendingPathComponent(".claude")
        let dest = (destDir as NSString).appendingPathComponent("settings.local.json")
        try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        try? fm.copyItem(atPath: source, toPath: dest)
    }

    static func removeWorktree(repoPath: String, worktreePath: String) throws {
        try run(["-C", repoPath, "worktree", "remove", "--force", worktreePath])
    }

    /// Finds the path of an existing worktree checked out on the given branch.
    /// Returns `nil` if no worktree is checked out on that branch.
    static func findExistingWorktree(repoPath: String, branch: String) throws -> String? {
        let output = try run(["-C", repoPath, "worktree", "list", "--porcelain"])
        return parseWorktreeList(output, branch: branch)
    }

    /// Parses `git worktree list --porcelain` output to find the path for a given branch.
    static func parseWorktreeList(_ output: String, branch: String) -> String? {
        let blocks = output.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            var path: String?
            var blockBranch: String?
            for line in lines {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("branch refs/heads/") {
                    blockBranch = String(line.dropFirst("branch refs/heads/".count))
                }
            }
            if blockBranch == branch, let path {
                return path
            }
        }
        return nil
    }

    static func deleteLocalBranch(repoPath: String, branch: String) throws {
        try run(["-C", repoPath, "branch", "-D", branch])
    }

    @discardableResult
    static func pull(path: String) throws -> String {
        try run(["-C", path, "pull"])
    }

    /// Returns the command string that `push` will execute, without actually running it.
    static func pushCommand(path: String) -> String {
        let hasUpstream = (try? run(["-C", path, "rev-parse", "--abbrev-ref", "@{u}"])) != nil
        if hasUpstream {
            return "git push"
        } else if let branch = currentBranch(repoPath: path) {
            return "git push --set-upstream origin \(branch)"
        } else {
            return "git push"
        }
    }

    @discardableResult
    static func push(path: String) throws -> String {
        let hasUpstream = (try? run(["-C", path, "rev-parse", "--abbrev-ref", "@{u}"])) != nil
        if hasUpstream {
            return try run(["-C", path, "push"])
        } else {
            guard let branch = currentBranch(repoPath: path) else {
                return try run(["-C", path, "push"])
            }
            return try run(["-C", path, "push", "--set-upstream", "origin", branch])
        }
    }

    @discardableResult
    static func fetch(path: String) throws -> String {
        try run(["-C", path, "fetch"])
    }

    @discardableResult
    static func stash(path: String) throws -> String {
        try run(["-C", path, "stash"])
    }

    @discardableResult
    static func stashPop(path: String) throws -> String {
        try run(["-C", path, "stash", "pop"])
    }

    @discardableResult
    static func checkout(path: String, branch: String) throws -> String {
        try run(["-C", path, "checkout", branch])
    }

    /// Discards all uncommitted changes in a single file.
    /// For tracked files: restores to HEAD and unstages any staged changes.
    /// For untracked files (`isUntracked == true`): deletes the file from disk.
    static func discardFile(repoPath: String, filePath: String, isUntracked: Bool) throws {
        if isUntracked {
            let fullPath = (repoPath as NSString).appendingPathComponent(filePath)
            try FileManager.default.removeItem(atPath: fullPath)
        } else {
            // Reset staged changes, then restore working tree
            try run(["-C", repoPath, "checkout", "HEAD", "--", filePath])
        }
    }

    /// Discards a single hunk by constructing a reverse patch and applying it.
    /// Not supported for untracked files (they are synthetic diffs with no HEAD to revert to).
    static func discardHunk(repoPath: String, file: DiffFile, hunk: DiffHunk) throws {
        // Build a minimal unified diff patch for this single hunk
        var patch = "--- a/\(file.oldPath)\n"
        patch += "+++ b/\(file.newPath)\n"
        patch += "\(hunk.header)\n"
        for line in hunk.lines {
            switch line.type {
            case .added:
                patch += "+\(line.content)\n"
            case .removed:
                patch += "-\(line.content)\n"
            case .context:
                patch += " \(line.content)\n"
            }
        }

        // Write to a temp file and apply in reverse
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("termhub-hunk-\(UUID().uuidString).patch")
        try patch.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try run(["-C", repoPath, "apply", "--reverse", tempURL.path])
    }

    /// Returns (linesAdded, linesDeleted) for uncommitted changes (staged + unstaged), including untracked files.
    static func diffStats(path: String) -> (added: Int, deleted: Int) {
        var added = 0
        var deleted = 0
        do {
            let output = try run(["-C", path, "diff", "--numstat", "HEAD"])
            for line in output.components(separatedBy: "\n") where !line.isEmpty {
                let parts = line.split(separator: "\t")
                guard parts.count >= 2 else { continue }
                // Binary files show "-" instead of numbers
                added += Int(parts[0]) ?? 0
                deleted += Int(parts[1]) ?? 0
            }
        } catch {
            // no tracked changes
        }

        // Count lines in untracked files as additions.
        for file in untrackedFiles(path: path) {
            let fullPath = (path as NSString).appendingPathComponent(file)
            guard let data = FileManager.default.contents(atPath: fullPath),
                  !data.prefix(min(data.count, 8192)).contains(0x00),
                  let content = String(data: data, encoding: .utf8),
                  !content.isEmpty
            else { continue }
            var lines = content.components(separatedBy: "\n")
            if lines.last == "" { lines.removeLast() }
            added += lines.count
        }

        return (added, deleted)
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
        let branch = currentBranch(repoPath: path)
        return GitStatus(linesAdded: added, linesDeleted: deleted, ahead: ahead, behind: behind, currentBranch: branch)
    }

    /// Returns a list of untracked file paths (relative to the repo root), excluding ignored files.
    static func untrackedFiles(path: String) -> [String] {
        do {
            let output = try run(["-C", path, "ls-files", "--others", "--exclude-standard"])
            guard !output.isEmpty else { return [] }
            return output.components(separatedBy: "\n").filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    /// Builds a synthetic unified diff string for an untracked (new) file so it appears in the diff view.
    private static func syntheticDiffForNewFile(path repoPath: String, relativePath: String) -> String? {
        let fullPath = (repoPath as NSString).appendingPathComponent(relativePath)
        guard let data = FileManager.default.contents(atPath: fullPath) else { return nil }

        // Skip binary files — check for null bytes in the first 8KB (same heuristic git uses).
        let checkLength = min(data.count, 8192)
        let isBinary = data.prefix(checkLength).contains(0x00)
        if isBinary {
            return """
            diff --git a/\(relativePath) b/\(relativePath)
            new file mode 100644
            Binary files /dev/null and b/\(relativePath) differ
            """
        }

        guard let content = String(data: data, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n")
        // Remove trailing empty element produced by a final newline
        let effectiveLines = lines.last == "" ? Array(lines.dropLast()) : lines
        let lineCount = effectiveLines.count
        guard lineCount > 0 else { return nil }

        var result = """
        diff --git a/\(relativePath) b/\(relativePath)
        new file mode 100644
        --- /dev/null
        +++ b/\(relativePath)
        @@ -0,0 +1,\(lineCount) @@\n
        """
        result += effectiveLines.map { "+\($0)" }.joined(separator: "\n")
        return result
    }

    /// Returns the raw unified diff output for uncommitted changes (staged + unstaged) vs HEAD,
    /// including untracked files.
    static func diff(path: String) -> String {
        var output = ""
        do {
            output = try run(["-C", path, "diff", "HEAD"])
        } catch {
            // empty – no tracked changes
        }

        let untracked = untrackedFiles(path: path)
        for file in untracked {
            if let synth = syntheticDiffForNewFile(path: path, relativePath: file) {
                if !output.isEmpty && !output.hasSuffix("\n") {
                    output += "\n"
                }
                output += synth
            }
        }

        return output
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
