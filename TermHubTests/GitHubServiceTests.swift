import Foundation
import Testing
@testable import TermHub

@Suite("GitHubService Tests", .serialized)
struct GitHubServiceTests {
    private let mock = MockCommandRunner()

    init() {
        GitHubService.commandRunner = mock
        GitHubService.ghPathOverride = "/usr/local/bin/gh"
    }

    @Test("returns URL for an open pull request")
    func openPullRequest() {
        mock.enqueueSuccess(#"{"state":"OPEN","url":"https://github.com/acme/repo/pull/42"}"#)

        let url = GitHubService.openPullRequestURL(repositoryPath: "/tmp/worktree")

        #expect(url?.absoluteString == "https://github.com/acme/repo/pull/42")
        #expect(mock.lastCall?.executablePath == "/usr/local/bin/gh")
        #expect(mock.lastCall?.arguments == ["pr", "view", "--json", "state,url"])
        #expect(mock.lastCall?.currentDirectoryURL?.path == "/tmp/worktree")
    }

    @Test("hides closed pull requests")
    func closedPullRequest() {
        mock.enqueueSuccess(#"{"state":"CLOSED","url":"https://github.com/acme/repo/pull/42"}"#)

        #expect(GitHubService.openPullRequestURL(repositoryPath: "/tmp/worktree") == nil)
    }

    @Test("rejects malformed and non-HTTPS responses")
    func invalidResponses() {
        mock.enqueueSuccess("not json")
        mock.enqueueSuccess(#"{"state":"OPEN","url":"http://github.com/acme/repo/pull/42"}"#)

        #expect(GitHubService.openPullRequestURL(repositoryPath: "/tmp/worktree") == nil)
        #expect(GitHubService.openPullRequestURL(repositoryPath: "/tmp/worktree") == nil)
    }

    @Test("returns nil when GitHub CLI fails")
    func commandFailure() {
        mock.enqueueFailure("no pull requests found")

        #expect(GitHubService.openPullRequestURL(repositoryPath: "/tmp/worktree") == nil)
    }
}
