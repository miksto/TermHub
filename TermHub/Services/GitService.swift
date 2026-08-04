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

    /// Returns the filesystem locations whose changes can affect git state for the given working tree.
    /// This includes the working tree itself plus git's administrative directories, which for linked
    /// worktrees live outside the worktree root.
    static func gitMetadataWatchPaths(path: String) -> [String] {
        var seen: Set<String> = []
        var paths: [String] = []

        func appendPath(_ candidate: String?) {
            guard let candidate, !candidate.isEmpty else { return }
            let standardized = (candidate as NSString).standardizingPath
            if seen.insert(standardized).inserted {
                paths.append(standardized)
            }
        }

        appendPath(path)
        appendPath(absoluteGitDir(path: path))
        appendPath(gitCommonDir(path: path))

        return paths
    }

    static func listBranches(repoPath: String) throws -> [String] {
        let output = try run(["-C", repoPath, "branch", "--format=%(refname:short)"])
        guard !output.isEmpty else { return [] }
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    /// Creates and checks out a local branch in the repository's current worktree.
    static func createBranch(repoPath: String, branch: String, startPoint: String? = nil) throws {
        var args = ["-C", repoPath, "checkout", "-b", branch]
        if let startPoint {
            args.append(startPoint)
        }
        try run(args)
    }

    static func listWorktreeBranchesWithDatesAndCurrent(repoPath: String) throws -> [BranchInfo] {
        let output = try run([
            "-C", repoPath,
            "for-each-ref",
            "--sort=-committerdate",
            "--format=%(refname)\t%(refname:short)\t%(committerdate:iso8601)\t%(HEAD)",
            "refs/heads/",
            "refs/remotes/",
        ])
        guard !output.isEmpty else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        struct ParsedBranch {
            let name: String
            let date: Date
            let isCurrentBranch: Bool
            let remoteName: String?
            let remoteStartPoint: String?
        }

        var parsed: [ParsedBranch] = []
        var localBranchNames: Set<String> = []

        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count >= 3,
                  let date = formatter.date(from: String(parts[2]))
            else { continue }

            let fullRef = String(parts[0])
            let shortRef = String(parts[1])
            let isCurrentBranch = parts.count >= 4 && parts[3] == "*"

            if fullRef.hasPrefix("refs/heads/") {
                let name = String(fullRef.dropFirst("refs/heads/".count))
                localBranchNames.insert(name)
                parsed.append(ParsedBranch(
                    name: name,
                    date: date,
                    isCurrentBranch: isCurrentBranch,
                    remoteName: nil,
                    remoteStartPoint: nil
                ))
                continue
            }

            guard fullRef.hasPrefix("refs/remotes/") else { continue }
            let remotePath = String(fullRef.dropFirst("refs/remotes/".count))
            guard let slashIndex = remotePath.firstIndex(of: "/") else { continue }
            let remoteName = String(remotePath[..<slashIndex])
            let branchName = String(remotePath[remotePath.index(after: slashIndex)...])
            guard branchName != "HEAD" else { continue }

            parsed.append(ParsedBranch(
                name: branchName,
                date: date,
                isCurrentBranch: false,
                remoteName: remoteName,
                remoteStartPoint: shortRef
            ))
        }

        return parsed.compactMap { branch in
            if branch.remoteStartPoint != nil, localBranchNames.contains(branch.name) {
                return nil
            }
            return BranchInfo(
                name: branch.name,
                lastCommitDate: branch.date,
                isCurrentBranch: branch.isCurrentBranch,
                hasActiveSession: false,
                remoteName: branch.remoteName,
                remoteStartPoint: branch.remoteStartPoint
            )
        }
    }

    static func currentBranch(repoPath: String) -> String? {
        guard let output = try? run(["-C", repoPath, "symbolic-ref", "--short", "HEAD"]),
              !output.isEmpty else {
            return nil
        }
        return output
    }

    /// Returns the repo's default branch (e.g. "main" or "develop") by reading
    /// `refs/remotes/origin/HEAD`. Falls back to `currentBranch` if unavailable.
    static func defaultBranch(repoPath: String) -> String? {
        if let output = try? run(["-C", repoPath, "symbolic-ref", "refs/remotes/origin/HEAD"]),
           !output.isEmpty {
            // output is e.g. "refs/remotes/origin/main" — strip the prefix
            let prefix = "refs/remotes/origin/"
            if output.hasPrefix(prefix) {
                return String(output.dropFirst(prefix.count))
            }
            return output
        }
        return currentBranch(repoPath: repoPath)
    }

    /// Returns the comparison branch used to identify commits introduced by a
    /// non-primary branch. This deliberately does not fall back to the current
    /// branch: doing so would make a feature branch appear to have no commits.
    static func commitHistoryBaseBranch(repoPath: String) -> String? {
        if let output = try? run([
            "-C", repoPath,
            "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD",
        ]), !output.isEmpty {
            return output
        }

        for branch in ["main", "master", "develop"] {
            if (try? run([
                "-C", repoPath,
                "rev-parse", "--verify", "--quiet", "refs/heads/\(branch)",
            ])) != nil {
                return branch
            }
        }
        return nil
    }

    /// Loads commit history for the currently checked-out branch.
    /// Primary branches are capped to the latest 20 commits. Other branches
    /// include every commit reachable from HEAD but not the resolved base branch.
    static func commitHistory(path: String) -> GitCommitHistory {
        guard let branch = currentBranch(repoPath: path) else {
            return .unavailable("Commit history is unavailable for a detached HEAD.")
        }

        do {
            if ["main", "master", "develop"].contains(branch) {
                return .loaded(try commits(path: path, revisionRange: "HEAD", limit: 20))
            }

            guard let baseBranch = commitHistoryBaseBranch(repoPath: path) else {
                return .unavailable(
                    "Couldn't determine a base branch. Expected origin/HEAD, main, master, or develop."
                )
            }
            return .loaded(try commits(path: path, revisionRange: "\(baseBranch)..HEAD"))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Returns the raw patch for a committed change. `--first-parent` makes
    /// merge commits inspectable by comparing them with their first parent.
    static func commitDiff(path: String, commitHash: String) throws -> String {
        try run([
            "-C", path,
            "show", "--format=", "--find-renames", "--first-parent", commitHash,
        ])
    }

    private static func commits(path: String, revisionRange: String, limit: Int? = nil) throws -> [GitCommit] {
        var arguments = [
            "-C", path,
            "log",
            "--format=%H%x00%an%x00%aI%x00%B%x00",
        ]
        if let limit {
            arguments.append("-\(limit)")
        }
        arguments.append(revisionRange)
        return parseCommits(try run(arguments))
    }

    /// Parses the NUL-separated fields emitted by `commits`. Git commit
    /// messages cannot contain NUL bytes, so multiline bodies remain intact
    /// without requiring fragile line-based parsing.
    static func parseCommits(_ output: String) -> [GitCommit] {
        let dateFormatter = ISO8601DateFormatter()

        var fields = output.components(separatedBy: "\0")
        if fields.last == "" {
            fields.removeLast()
        }
        guard fields.count.isMultiple(of: 4) else { return [] }

        return stride(from: 0, to: fields.count, by: 4).compactMap { index in
            guard let date = dateFormatter.date(from: fields[index + 2]) else { return nil }
            return GitCommit(
                // `git log --format` appends a newline after every record, so
                // the next record's hash begins with that newline.
                hash: fields[index].trimmingCharacters(in: .whitespacesAndNewlines),
                authorName: fields[index + 1],
                authoredDate: date,
                message: fields[index + 3].trimmingCharacters(in: .newlines)
            )
        }
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

    static func addWorktreeTrackingRemote(repoPath: String, branch: String, remoteStartPoint: String) throws -> String {
        let path = worktreePath(repoPath: repoPath, branch: branch)
        try ensureWorktreeContainer(repoPath: repoPath)
        try run(["-C", repoPath, "worktree", "add", "--track", "-b", branch, path, remoteStartPoint])
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

    static func removeWorktree(repoPath: String, worktreePath: String, force: Bool = false) throws {
        var arguments = ["-C", repoPath, "worktree", "remove"]
        if force {
            arguments.append("--force")
        }
        arguments.append(worktreePath)
        try run(arguments)
    }

    static func listWorktrees(repoPath: String, folderID: UUID) throws -> [GitWorktree] {
        let output = try run(["-C", repoPath, "worktree", "list", "--porcelain"])
        return parseWorktreeList(output, folderID: folderID)
    }

    static func parseWorktreeList(_ output: String, folderID: UUID) -> [GitWorktree] {
        output.components(separatedBy: "\n\n").compactMap { block in
            var path: String?
            var head: String?
            var branch: String?
            var isDetached = false
            var isBare = false
            var isLocked = false
            var lockReason: String?
            var isPrunable = false
            var prunableReason: String?

            for line in block.components(separatedBy: "\n") {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    head = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch refs/heads/") {
                    branch = String(line.dropFirst("branch refs/heads/".count))
                } else if line == "detached" {
                    isDetached = true
                } else if line == "bare" {
                    isBare = true
                } else if line == "locked" || line.hasPrefix("locked ") {
                    isLocked = true
                    let reason = line == "locked" ? "" : String(line.dropFirst("locked ".count))
                    lockReason = reason.isEmpty ? nil : reason
                } else if line == "prunable" || line.hasPrefix("prunable ") {
                    isPrunable = true
                    let reason = line == "prunable" ? "" : String(line.dropFirst("prunable ".count))
                    prunableReason = reason.isEmpty ? nil : reason
                }
            }

            guard let path, !path.isEmpty, let head, !head.isEmpty else { return nil }
            return GitWorktree(
                folderID: folderID,
                path: path,
                normalizedPath: GitWorktree.normalizePath(path),
                head: head,
                branch: branch,
                isDetached: isDetached || branch == nil,
                isBare: isBare,
                isLocked: isLocked,
                lockReason: lockReason,
                isPrunable: isPrunable,
                prunableReason: prunableReason
            )
        }
    }

    /// Finds the path of an existing worktree checked out on the given branch.
    /// Returns `nil` if no worktree is checked out on that branch.
    static func findExistingWorktree(repoPath: String, branch: String) throws -> String? {
        try listWorktrees(repoPath: repoPath, folderID: UUID())
            .first(where: { $0.branch == branch })?
            .path
    }

    /// Parses `git worktree list --porcelain` output to find the path for a given branch.
    static func parseWorktreeList(_ output: String, branch: String) -> String? {
        parseWorktreeList(output, folderID: UUID())
            .first(where: { $0.branch == branch })?
            .path
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
        (try? checkedDiffStats(path: path)) ?? (0, 0)
    }

    /// Status refreshes use the throwing variant so a transient git failure does not get
    /// mistaken for a clean working tree and overwrite the last known-good status.
    private static func checkedDiffStats(path: String) throws -> (added: Int, deleted: Int) {
        var added = 0
        var deleted = 0
        // Repositories without an initial commit do not have HEAD. Their tracked
        // changes are all staged, so compare the index instead.
        let hasHead: Bool
        do {
            _ = try run(["-C", path, "rev-parse", "--verify", "--quiet", "HEAD"])
            hasHead = true
        } catch GitServiceError.commandFailed(let message) where message.isEmpty {
            // `--quiet` intentionally produces no diagnostic for an unborn HEAD.
            hasHead = false
        } catch {
            throw error
        }
        let diffArguments = hasHead
            ? ["-C", path, "diff", "--numstat", "HEAD"]
            : ["-C", path, "diff", "--cached", "--numstat"]
        let output = try run(diffArguments)
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t")
            guard parts.count >= 2 else { continue }
            // Binary files show "-" instead of numbers
            added += Int(parts[0]) ?? 0
            deleted += Int(parts[1]) ?? 0
        }

        // Count lines in untracked files as additions.
        let untrackedOutput = try run(["-C", path, "ls-files", "--others", "--exclude-standard"])
        let untrackedFiles = untrackedOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
        for file in untrackedFiles {
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

    static func status(path: String) throws -> GitStatus {
        // Validate the working tree first. In particular, do not turn a removed or
        // temporarily inaccessible worktree into an all-zero status.
        _ = try run(["-C", path, "rev-parse", "--git-dir"])
        let (added, deleted) = try checkedDiffStats(path: path)
        let (ahead, behind) = aheadBehind(path: path)
        // Unlike symbolic-ref, `branch --show-current` succeeds with empty output
        // for a valid detached HEAD, while still surfacing real command failures.
        let branchOutput = try run(["-C", path, "branch", "--show-current"])
        let branch = branchOutput.isEmpty ? nil : branchOutput
        return GitStatus(linesAdded: added, linesDeleted: deleted, ahead: ahead, behind: behind, currentBranch: branch)
    }

    private static func absoluteGitDir(path: String) -> String? {
        guard let output = try? run(["-C", path, "rev-parse", "--absolute-git-dir"]),
              !output.isEmpty else {
            return nil
        }
        return output
    }

    private static func gitCommonDir(path: String) -> String? {
        guard let output = try? run(["-C", path, "rev-parse", "--git-common-dir"]),
              !output.isEmpty else {
            return nil
        }

        if (output as NSString).isAbsolutePath {
            return output
        }

        return ((path as NSString).appendingPathComponent(output) as NSString).standardizingPath
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
