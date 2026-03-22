import Foundation
import Testing
@testable import TermHub

@Suite("GitService Tests")
struct GitServiceTests {
    @Test("sanitizeBranchName replaces slashes with dashes")
    func sanitizeBranchName() {
        #expect(GitService.sanitizeBranchName("feature/login") == "feature-login")
        #expect(GitService.sanitizeBranchName("fix/ui/button") == "fix-ui-button")
        #expect(GitService.sanitizeBranchName("main") == "main")
        #expect(GitService.sanitizeBranchName("release/v2.0/rc1") == "release-v2.0-rc1")
    }

    @Test("worktreePath constructs correct path")
    func worktreePathConstruction() {
        let path = GitService.worktreePath(repoPath: "/Users/dev/my-repo", branch: "feature/login")
        #expect(path == "/Users/dev/my-repo-termhub/feature-login")
    }

    @Test("worktreePath with simple branch name")
    func worktreePathSimpleBranch() {
        let path = GitService.worktreePath(repoPath: "/Users/dev/project", branch: "hotfix")
        #expect(path == "/Users/dev/project-termhub/hotfix")
    }

    @Test("worktreePath with nested slashes")
    func worktreePathNestedSlashes() {
        let path = GitService.worktreePath(repoPath: "/home/user/app", branch: "a/b/c/d")
        #expect(path == "/home/user/app-termhub/a-b-c-d")
    }

    @Test("worktreeContainerPath constructs correct path")
    func worktreeContainerPath() {
        let path = GitService.worktreeContainerPath(repoPath: "/Users/dev/my-repo")
        #expect(path == "/Users/dev/my-repo-termhub")
    }

    // MARK: - parseWorktreeList

    @Test("parseWorktreeList finds matching branch")
    func parseWorktreeListMatch() {
        let output = """
        worktree /Users/dev/my-repo
        HEAD abc1234
        branch refs/heads/main

        worktree /tmp/test-wt
        HEAD def5678
        branch refs/heads/feature/login

        """
        let result = GitService.parseWorktreeList(output, branch: "feature/login")
        #expect(result == "/tmp/test-wt")
    }

    @Test("parseWorktreeList returns nil when no match")
    func parseWorktreeListNoMatch() {
        let output = """
        worktree /Users/dev/my-repo
        HEAD abc1234
        branch refs/heads/main

        """
        let result = GitService.parseWorktreeList(output, branch: "feature/login")
        #expect(result == nil)
    }

    @Test("parseWorktreeList with multiple worktrees returns correct one")
    func parseWorktreeListMultiple() {
        let output = """
        worktree /Users/dev/my-repo
        HEAD abc1234
        branch refs/heads/main

        worktree /tmp/wt-a
        HEAD 111111
        branch refs/heads/feature/a

        worktree /tmp/wt-b
        HEAD 222222
        branch refs/heads/feature/b

        """
        #expect(GitService.parseWorktreeList(output, branch: "feature/a") == "/tmp/wt-a")
        #expect(GitService.parseWorktreeList(output, branch: "feature/b") == "/tmp/wt-b")
        #expect(GitService.parseWorktreeList(output, branch: "feature/c") == nil)
    }

    @Test("parseWorktreeList with branch containing slashes")
    func parseWorktreeListSlashedBranch() {
        let output = """
        worktree /home/user/wt
        HEAD aaa
        branch refs/heads/release/v2.0/rc1

        """
        #expect(GitService.parseWorktreeList(output, branch: "release/v2.0/rc1") == "/home/user/wt")
    }

    @Test("parseWorktreeList skips detached HEAD entries")
    func parseWorktreeListDetachedHead() {
        let output = """
        worktree /Users/dev/my-repo
        HEAD abc1234
        branch refs/heads/main

        worktree /tmp/detached-wt
        HEAD def5678
        detached

        """
        #expect(GitService.parseWorktreeList(output, branch: "main") == "/Users/dev/my-repo")
        #expect(GitService.parseWorktreeList(output, branch: "detached") == nil)
    }
}
