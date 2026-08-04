import Foundation
import Testing
@testable import TermHub

@Suite("GitService I/O Tests")
struct GitServiceIOTests {
    private let mock = MockCommandRunner()

    init() {
        GitService.commandRunner = mock
    }

    // MARK: - isGitRepo

    @Test("isGitRepo returns true on success")
    func isGitRepoTrue() {
        mock.enqueueSuccess(".git")
        #expect(GitService.isGitRepo(path: "/tmp/repo") == true)

        let call = mock.lastCall!
        #expect(call.arguments.contains("rev-parse"))
        #expect(call.arguments.contains("--git-dir"))
    }

    @Test("isGitRepo returns false on failure")
    func isGitRepoFalse() {
        mock.enqueueFailure("fatal: not a git repository")
        #expect(GitService.isGitRepo(path: "/tmp/not-a-repo") == false)
    }

    // MARK: - listBranches

    @Test("listBranches parses branch output")
    func listBranchesParsesOutput() throws {
        mock.enqueueSuccess("main\nfeature/login\ndevelop")
        let branches = try GitService.listBranches(repoPath: "/tmp/repo")
        #expect(branches == ["main", "feature/login", "develop"])
    }

    @Test("listBranches returns empty for no branches")
    func listBranchesEmpty() throws {
        mock.enqueueSuccess("")
        let branches = try GitService.listBranches(repoPath: "/tmp/repo")
        #expect(branches.isEmpty)
    }

    @Test("listBranches throws on git error")
    func listBranchesThrows() {
        mock.enqueueFailure("fatal: not a git repository")
        #expect(throws: GitServiceError.self) {
            try GitService.listBranches(repoPath: "/tmp/bad")
        }
    }

    // MARK: - listWorktreeBranchesWithDatesAndCurrent

    @Test("listWorktreeBranchesWithDatesAndCurrent merges local and remote refs")
    func listWorktreeBranchesMergesRefs() throws {
        mock.enqueueSuccess("""
        refs/heads/main\tmain\t2024-01-15 10:30:00 +0000\t*
        refs/remotes/origin/main\torigin/main\t2024-01-15 09:00:00 +0000\t
        refs/remotes/origin/feature/login\torigin/feature/login\t2024-01-14 08:00:00 +0000\t
        refs/remotes/upstream/feature/login\tupstream/feature/login\t2024-01-13 08:00:00 +0000\t
        refs/remotes/origin/HEAD\torigin/HEAD\t2024-01-12 08:00:00 +0000\t
        """)

        let branches = try GitService.listWorktreeBranchesWithDatesAndCurrent(repoPath: "/tmp/repo")

        #expect(branches.count == 3)
        #expect(branches[0].name == "main")
        #expect(branches[0].isCurrentBranch == true)
        #expect(branches[0].remoteName == nil)
        #expect(branches[1].name == "feature/login")
        #expect(branches[1].remoteName == "origin")
        #expect(branches[1].remoteStartPoint == "origin/feature/login")
        #expect(branches[2].remoteName == "upstream")
        #expect(branches.contains { $0.remoteStartPoint == "origin/HEAD" } == false)
    }

    @Test("listWorktreeBranchesWithDatesAndCurrent drops remote when local exists")
    func listWorktreeBranchesDropsDuplicateRemote() throws {
        mock.enqueueSuccess("""
        refs/heads/feature/login\tfeature/login\t2024-01-15 10:30:00 +0000\t
        refs/remotes/origin/feature/login\torigin/feature/login\t2024-01-14 08:00:00 +0000\t
        """)

        let branches = try GitService.listWorktreeBranchesWithDatesAndCurrent(repoPath: "/tmp/repo")

        #expect(branches.count == 1)
        #expect(branches[0].name == "feature/login")
        #expect(branches[0].remoteStartPoint == nil)
    }

    // MARK: - currentBranch

    @Test("currentBranch returns branch name")
    func currentBranchReturns() {
        mock.enqueueSuccess("main")
        #expect(GitService.currentBranch(repoPath: "/tmp/repo") == "main")
    }

    @Test("currentBranch returns nil on failure")
    func currentBranchNil() {
        mock.enqueueFailure("fatal: ref HEAD is not a symbolic ref")
        #expect(GitService.currentBranch(repoPath: "/tmp/repo") == nil)
    }

    @Test("currentBranch returns nil for empty output")
    func currentBranchEmpty() {
        mock.enqueueSuccess("")
        #expect(GitService.currentBranch(repoPath: "/tmp/repo") == nil)
    }

    // MARK: - Commit history

    @Test("commit history base prefers the remote default branch")
    func commitHistoryBasePrefersRemoteDefault() {
        mock.enqueueSuccess("origin/develop")

        #expect(GitService.commitHistoryBaseBranch(repoPath: "/tmp/repo") == "origin/develop")
        #expect(mock.lastCall?.arguments == [
            "-C", "/tmp/repo", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD",
        ])
    }

    @Test("commit history base falls back through local primary branches")
    func commitHistoryBaseFallsBackToLocalBranches() {
        mock.enqueueFailure()
        mock.enqueueFailure()
        mock.enqueueSuccess("abc123")

        #expect(GitService.commitHistoryBaseBranch(repoPath: "/tmp/repo") == "master")
        #expect(mock.calls.last?.arguments.last == "refs/heads/master")
    }

    @Test("primary branch history is limited to twenty commits")
    func primaryBranchHistoryIsLimited() {
        mock.enqueueSuccess("main")
        mock.enqueueSuccess(commitLogOutput())

        let history = GitService.commitHistory(path: "/tmp/repo")

        guard case .loaded(let commits) = history else {
            Issue.record("Expected loaded commit history")
            return
        }
        #expect(commits.count == 1)
        #expect(mock.lastCall?.arguments.contains("-20") == true)
        #expect(mock.lastCall?.arguments.last == "HEAD")
    }

    @Test("feature branch history uses only commits outside its base branch")
    func featureBranchHistoryUsesBaseRange() {
        mock.enqueueSuccess("feature/login")
        mock.enqueueSuccess("origin/main")
        mock.enqueueSuccess(commitLogOutput())

        let history = GitService.commitHistory(path: "/tmp/repo")

        guard case .loaded(let commits) = history else {
            Issue.record("Expected loaded commit history")
            return
        }
        #expect(commits[0].message == "Add login\n\nBody line")
        #expect(commits[0].messagePreview == "Add login\n\nBody line")
        #expect(mock.lastCall?.arguments.contains("-20") == false)
        #expect(mock.lastCall?.arguments.last == "origin/main..HEAD")
    }

    @Test("commit history is unavailable for detached HEAD")
    func commitHistoryDetachedHead() {
        mock.enqueueFailure("fatal: ref HEAD is not a symbolic ref")

        #expect(GitService.commitHistory(path: "/tmp/repo") == .unavailable("Commit history is unavailable for a detached HEAD."))
        #expect(mock.callCount == 1)
    }

    @Test("commit parser preserves multiline messages and caps previews at five lines")
    func commitParserPreservesMultilineMessages() {
        let separator = "\0"
        let raw = "deadbeef\(separator)Ada Lovelace\(separator)2025-02-03T04:05:06Z\(separator)one\ntwo\nthree\nfour\nfive\nsix\(separator)"

        let commits = GitService.parseCommits(raw)

        #expect(commits.count == 1)
        #expect(commits[0].authorName == "Ada Lovelace")
        #expect(commits[0].messagePreview == "one\ntwo\nthree\nfour\nfive")
    }

    @Test("commit diff uses a read-only first-parent show command")
    func commitDiffCommand() throws {
        mock.enqueueSuccess("diff --git a/a b/a")

        _ = try GitService.commitDiff(path: "/tmp/repo", commitHash: "deadbeef")

        #expect(mock.lastCall?.arguments == [
            "-C", "/tmp/repo", "show", "--format=", "--find-renames", "--first-parent", "deadbeef",
        ])
    }

    private func commitLogOutput() -> String {
        let separator = "\0"
        return "deadbeef\(separator)Ada Lovelace\(separator)2025-02-03T04:05:06Z\(separator)Add login\n\nBody line\(separator)"
    }

    // MARK: - status

    @Test("status returns branch and diff statistics")
    func statusReturnsSnapshot() throws {
        mock.enqueueSuccess(".git")
        mock.enqueueSuccess("abc123")
        mock.enqueueSuccess("12\t4\tSources/App.swift")
        mock.enqueueSuccess("")
        mock.enqueueSuccess("2\t1")
        mock.enqueueSuccess("feature/status-refresh")

        let status = try GitService.status(path: "/tmp/repo")

        #expect(status.linesAdded == 12)
        #expect(status.linesDeleted == 4)
        #expect(status.ahead == 2)
        #expect(status.behind == 1)
        #expect(status.currentBranch == "feature/status-refresh")
    }

    @Test("status supports a repository without an initial commit")
    func statusSupportsUnbornHead() throws {
        mock.enqueueSuccess(".git")
        mock.enqueueFailure("")
        mock.enqueueSuccess("7\t0\tREADME.md")
        mock.enqueueSuccess("")
        mock.enqueueFailure("fatal: no upstream configured")
        mock.enqueueSuccess("main")

        let status = try GitService.status(path: "/tmp/repo")

        #expect(status.linesAdded == 7)
        #expect(status.linesDeleted == 0)
        #expect(status.currentBranch == "main")
        #expect(mock.calls[2].arguments.contains("--cached"))
    }

    @Test("status throws instead of returning an empty snapshot when git fails")
    func statusThrowsOnGitFailure() {
        mock.enqueueFailure("fatal: cannot change to '/tmp/missing'")

        #expect(throws: GitServiceError.self) {
            try GitService.status(path: "/tmp/missing")
        }
    }

    // MARK: - listBranchesWithDates

    @Test("listBranchesWithDates parses branch and date")
    func listBranchesWithDatesParsed() throws {
        mock.enqueueSuccess("main\t2024-01-15 10:30:00 +0000\nfeature/x\t2024-01-14 08:00:00 +0000")
        let result = try GitService.listBranchesWithDates(repoPath: "/tmp/repo")
        #expect(result.count == 2)
        #expect(result[0].branch == "main")
        #expect(result[1].branch == "feature/x")
    }

    @Test("listBranchesWithDates returns empty for no output")
    func listBranchesWithDatesEmpty() throws {
        mock.enqueueSuccess("")
        let result = try GitService.listBranchesWithDates(repoPath: "/tmp/repo")
        #expect(result.isEmpty)
    }

    @Test("listBranchesWithDates skips malformed lines")
    func listBranchesWithDatesSkipsMalformed() throws {
        mock.enqueueSuccess("main\t2024-01-15 10:30:00 +0000\nbadline\n")
        let result = try GitService.listBranchesWithDates(repoPath: "/tmp/repo")
        #expect(result.count == 1)
        #expect(result[0].branch == "main")
    }

    // MARK: - listBranchesWithDatesAndCurrent

    @Test("listBranchesWithDatesAndCurrent identifies current branch")
    func listBranchesWithDatesAndCurrentIdentifies() throws {
        mock.enqueueSuccess("main\t2024-01-15 10:30:00 +0000\t*\nfeature/x\t2024-01-14 08:00:00 +0000\t")
        let result = try GitService.listBranchesWithDatesAndCurrent(repoPath: "/tmp/repo")
        #expect(result.branches.count == 2)
        #expect(result.currentBranch == "main")
    }

    @Test("listBranchesWithDatesAndCurrent returns nil current when none starred")
    func listBranchesWithDatesAndCurrentNoCurrent() throws {
        mock.enqueueSuccess("main\t2024-01-15 10:30:00 +0000\t\ndev\t2024-01-14 08:00:00 +0000\t")
        let result = try GitService.listBranchesWithDatesAndCurrent(repoPath: "/tmp/repo")
        #expect(result.currentBranch == nil)
    }

    // MARK: - addWorktree

    @Test("listWorktrees uses stable porcelain command")
    func listWorktreesCommand() throws {
        mock.enqueueSuccess("""
        worktree /tmp/repo
        HEAD abc1234
        branch refs/heads/main
        """)

        let worktrees = try GitService.listWorktrees(repoPath: "/tmp/repo", folderID: UUID())

        #expect(worktrees.count == 1)
        #expect(mock.lastCall?.arguments == [
            "-C", "/tmp/repo", "worktree", "list", "--porcelain",
        ])
    }

    @Test("addWorktree runs correct git command")
    func addWorktreeCommand() throws {
        mock.enqueueSuccess()
        let path = try GitService.addWorktree(repoPath: "/tmp/repo", branch: "feature/login")

        #expect(path == "/tmp/repo-termhub/feature-login")
        let call = mock.lastCall!
        #expect(call.arguments.contains("worktree"))
        #expect(call.arguments.contains("add"))
        #expect(call.arguments.contains("feature/login"))
    }

    @Test("addWorktree throws worktreeAlreadyExists")
    func addWorktreeAlreadyExists() {
        mock.enqueueFailure("fatal: '/tmp/repo-termhub/feature' already exists")

        #expect {
            try GitService.addWorktree(repoPath: "/tmp/repo", branch: "feature")
        } throws: { error in
            (error as? GitServiceError) == .worktreeAlreadyExists
        }
    }

    @Test("normal worktree removal does not force")
    func removeWorktreeNormally() throws {
        mock.enqueueSuccess()

        try GitService.removeWorktree(repoPath: "/tmp/repo", worktreePath: "/tmp/worktree")

        #expect(mock.lastCall?.arguments == [
            "-C", "/tmp/repo", "worktree", "remove", "/tmp/worktree",
        ])
    }

    @Test("forced worktree removal includes force flag")
    func removeWorktreeForced() throws {
        mock.enqueueSuccess()

        try GitService.removeWorktree(
            repoPath: "/tmp/repo",
            worktreePath: "/tmp/worktree",
            force: true
        )

        #expect(mock.lastCall?.arguments == [
            "-C", "/tmp/repo", "worktree", "remove", "--force", "/tmp/worktree",
        ])
    }

    @Test("addWorktreeTrackingRemote uses track and local branch name")
    func addWorktreeTrackingRemoteCommand() throws {
        mock.enqueueSuccess()
        let path = try GitService.addWorktreeTrackingRemote(
            repoPath: "/tmp/repo",
            branch: "feature/login",
            remoteStartPoint: "origin/feature/login"
        )

        #expect(path == "/tmp/repo-termhub/feature-login")
        let call = mock.lastCall!
        #expect(call.arguments.contains("worktree"))
        #expect(call.arguments.contains("add"))
        #expect(call.arguments.contains("--track"))
        #expect(call.arguments.contains("-b"))
        #expect(call.arguments.contains("feature/login"))
        #expect(call.arguments.contains("origin/feature/login"))
    }

    // MARK: - addWorktreeNewBranch

    @Test("addWorktreeNewBranch includes -b flag")
    func addWorktreeNewBranchFlag() throws {
        mock.enqueueSuccess()
        let path = try GitService.addWorktreeNewBranch(repoPath: "/tmp/repo", newBranch: "new-feature")

        #expect(path == "/tmp/repo-termhub/new-feature")
        let call = mock.lastCall!
        #expect(call.arguments.contains("-b"))
        #expect(call.arguments.contains("new-feature"))
    }

    @Test("addWorktreeNewBranch with startPoint includes it")
    func addWorktreeNewBranchStartPoint() throws {
        mock.enqueueSuccess()
        _ = try GitService.addWorktreeNewBranch(repoPath: "/tmp/repo", newBranch: "fix", startPoint: "main")

        let call = mock.lastCall!
        #expect(call.arguments.last == "main")
    }

    // MARK: - createBranch

    @Test("createBranch uses git checkout -b")
    func createBranchCommand() throws {
        mock.enqueueSuccess()
        try GitService.createBranch(repoPath: "/tmp/repo", branch: "feature/login")

        #expect(mock.lastCall?.arguments == ["-C", "/tmp/repo", "checkout", "-b", "feature/login"])
    }

    @Test("createBranch includes start point")
    func createBranchStartPoint() throws {
        mock.enqueueSuccess()
        try GitService.createBranch(repoPath: "/tmp/repo", branch: "feature/login", startPoint: "main")

        #expect(mock.lastCall?.arguments == ["-C", "/tmp/repo", "checkout", "-b", "feature/login", "main"])
    }

    // MARK: - removeWorktree

    @Test("removeWorktree runs correct command")
    func removeWorktreeCommand() throws {
        mock.enqueueSuccess()
        try GitService.removeWorktree(repoPath: "/tmp/repo", worktreePath: "/tmp/repo-termhub/feature")

        let call = mock.lastCall!
        #expect(call.arguments.contains("worktree"))
        #expect(call.arguments.contains("remove"))
        #expect(!call.arguments.contains("--force"))
    }

    // MARK: - deleteLocalBranch

    @Test("deleteLocalBranch runs git branch -D")
    func deleteLocalBranchCommand() throws {
        mock.enqueueSuccess()
        try GitService.deleteLocalBranch(repoPath: "/tmp/repo", branch: "old-feature")

        let call = mock.lastCall!
        #expect(call.arguments.contains("branch"))
        #expect(call.arguments.contains("-D"))
        #expect(call.arguments.contains("old-feature"))
    }

    // MARK: - pull/push/fetch/stash

    @Test("pull runs correct command")
    func pullCommand() throws {
        mock.enqueueSuccess("Already up to date.")
        let output = try GitService.pull(path: "/tmp/repo")
        #expect(output == "Already up to date.")
        #expect(mock.lastCall!.arguments.contains("pull"))
    }

    @Test("fetch runs correct command")
    func fetchCommand() throws {
        mock.enqueueSuccess()
        try GitService.fetch(path: "/tmp/repo")
        #expect(mock.lastCall!.arguments.contains("fetch"))
    }

    @Test("stash runs correct command")
    func stashCommand() throws {
        mock.enqueueSuccess("Saved working directory")
        let output = try GitService.stash(path: "/tmp/repo")
        #expect(output == "Saved working directory")
        #expect(mock.lastCall!.arguments.contains("stash"))
    }

    @Test("stashPop runs correct command")
    func stashPopCommand() throws {
        mock.enqueueSuccess()
        try GitService.stashPop(path: "/tmp/repo")
        let call = mock.lastCall!
        #expect(call.arguments.contains("stash"))
        #expect(call.arguments.contains("pop"))
    }

    @Test("checkout runs correct command")
    func checkoutCommand() throws {
        mock.enqueueSuccess()
        try GitService.checkout(path: "/tmp/repo", branch: "develop")
        let call = mock.lastCall!
        #expect(call.arguments.contains("checkout"))
        #expect(call.arguments.contains("develop"))
    }

    // MARK: - push

    @Test("push with upstream runs simple push")
    func pushWithUpstream() throws {
        // First call: rev-parse @{u} succeeds (has upstream)
        mock.enqueueSuccess("origin/main")
        // Second call: git push
        mock.enqueueSuccess()

        try GitService.push(path: "/tmp/repo")

        #expect(mock.callCount == 2)
        let pushCall = mock.calls[1]
        #expect(pushCall.arguments == ["-C", "/tmp/repo", "push"])
    }

    @Test("push without upstream sets upstream")
    func pushWithoutUpstream() throws {
        // First call: rev-parse @{u} fails (no upstream)
        mock.enqueueFailure("fatal: no upstream configured")
        // Second call: symbolic-ref (currentBranch)
        mock.enqueueSuccess("feature/login")
        // Third call: git push --set-upstream
        mock.enqueueSuccess()

        try GitService.push(path: "/tmp/repo")

        #expect(mock.callCount == 3)
        let pushCall = mock.calls[2]
        #expect(pushCall.arguments.contains("--set-upstream"))
        #expect(pushCall.arguments.contains("origin"))
        #expect(pushCall.arguments.contains("feature/login"))
    }

    // MARK: - aheadBehind

    @Test("aheadBehind parses correct counts")
    func aheadBehindParsed() {
        mock.enqueueSuccess("3\t1")
        let result = GitService.aheadBehind(path: "/tmp/repo")
        #expect(result.ahead == 3)
        #expect(result.behind == 1)
    }

    @Test("aheadBehind returns zeros on failure")
    func aheadBehindFailure() {
        mock.enqueueFailure("fatal: no upstream")
        let result = GitService.aheadBehind(path: "/tmp/repo")
        #expect(result.ahead == 0)
        #expect(result.behind == 0)
    }

    @Test("aheadBehind returns zeros for malformed output")
    func aheadBehindMalformed() {
        mock.enqueueSuccess("garbage")
        let result = GitService.aheadBehind(path: "/tmp/repo")
        #expect(result.ahead == 0)
        #expect(result.behind == 0)
    }

    // MARK: - untrackedFiles

    @Test("untrackedFiles parses file list")
    func untrackedFilesParsed() {
        mock.enqueueSuccess("newfile.swift\ndir/other.txt")
        let files = GitService.untrackedFiles(path: "/tmp/repo")
        #expect(files == ["newfile.swift", "dir/other.txt"])
    }

    @Test("untrackedFiles returns empty on failure")
    func untrackedFilesFailure() {
        mock.enqueueFailure("fatal: not a git repo")
        let files = GitService.untrackedFiles(path: "/tmp/bad")
        #expect(files.isEmpty)
    }

    @Test("untrackedFiles returns empty for no untracked files")
    func untrackedFilesNone() {
        mock.enqueueSuccess("")
        let files = GitService.untrackedFiles(path: "/tmp/repo")
        #expect(files.isEmpty)
    }

    // MARK: - Error type mapping

    @Test("worktreeAlreadyExists error for 'already exists' message")
    func worktreeAlreadyExistsError() {
        mock.enqueueFailure("fatal: 'path' already exists")

        #expect {
            try GitService.removeWorktree(repoPath: "/tmp/repo", worktreePath: "/tmp/wt")
        } throws: { error in
            (error as? GitServiceError) == .worktreeAlreadyExists
        }
    }

    @Test("commandFailed error for other failures")
    func commandFailedError() {
        mock.enqueueFailure("permission denied")

        do {
            try GitService.fetch(path: "/tmp/repo")
            Issue.record("Expected error")
        } catch let error as GitServiceError {
            switch error {
            case .commandFailed(let msg):
                #expect(msg.contains("permission denied"))
            default:
                Issue.record("Wrong error variant: \(error)")
            }
        } catch {
            Issue.record("Wrong error type")
        }
    }

    // MARK: - findExistingWorktree

    @Test("findExistingWorktree passes correct arguments and parses result")
    func findExistingWorktreeArgs() throws {
        mock.enqueueSuccess("""
        worktree /tmp/repo
        HEAD abc123
        branch refs/heads/main

        worktree /tmp/repo-termhub/feature
        HEAD def456
        branch refs/heads/feature/login

        """)
        let result = try GitService.findExistingWorktree(repoPath: "/tmp/repo", branch: "feature/login")
        #expect(result == "/tmp/repo-termhub/feature")
        #expect(mock.lastCall!.arguments.contains("--porcelain"))
    }

    // MARK: - GitAction

    @Test("GitAction execute dispatches to correct service method")
    func gitActionExecute() throws {
        mock.enqueueSuccess()
        try GitAction.pull.execute(path: "/tmp/repo")
        #expect(mock.lastCall!.arguments.contains("pull"))

        mock.enqueueSuccess()
        try GitAction.fetch.execute(path: "/tmp/repo")
        #expect(mock.lastCall!.arguments.contains("fetch"))

        mock.enqueueSuccess()
        try GitAction.stash.execute(path: "/tmp/repo")
        #expect(mock.lastCall!.arguments.contains("stash"))

        mock.enqueueSuccess()
        try GitAction.stashPop.execute(path: "/tmp/repo")
        let call = mock.lastCall!
        #expect(call.arguments.contains("stash"))
        #expect(call.arguments.contains("pop"))
    }

    @Test("GitAction titles are non-empty")
    func gitActionTitles() {
        for action in GitAction.allCases {
            #expect(!action.title.isEmpty)
            #expect(!action.icon.isEmpty)
        }
    }
}
