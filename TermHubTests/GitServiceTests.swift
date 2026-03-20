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
        #expect(path == "/Users/dev/my-repo-feature-login")
    }

    @Test("worktreePath with simple branch name")
    func worktreePathSimpleBranch() {
        let path = GitService.worktreePath(repoPath: "/Users/dev/project", branch: "hotfix")
        #expect(path == "/Users/dev/project-hotfix")
    }

    @Test("worktreePath with nested slashes")
    func worktreePathNestedSlashes() {
        let path = GitService.worktreePath(repoPath: "/home/user/app", branch: "a/b/c/d")
        #expect(path == "/home/user/app-a-b-c-d")
    }
}
