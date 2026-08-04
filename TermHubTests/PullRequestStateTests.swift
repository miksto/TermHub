import Foundation
import Testing
@testable import TermHub

@Suite("Pull Request State Tests", .serialized)
struct PullRequestStateTests {
    @Test("selected git session loads and clears its pull request URL")
    @MainActor
    func selectedSessionPullRequest() async {
        let expectedURL = URL(string: "https://github.com/acme/repo/pull/42")!
        let lookup = PullRequestLookupService { path in
            path == "/tmp/worktree" ? expectedURL : nil
        }
        let state = AppState(
            persistence: NullPersistence(),
            pullRequestLookupService: lookup
        )
        let folder = ManagedFolder(path: "/tmp", isGitRepo: true)
        let session = TerminalSession(
            folderID: folder.id,
            title: "Feature",
            workingDirectory: "/tmp/worktree",
            worktreePath: "/tmp/worktree",
            branchName: "feature/pr"
        )
        state.folders = [folder]
        state.sessions = [session]

        state.selectedSessionID = session.id
        for _ in 0..<100 where state.isSelectedSessionPullRequestLoading {
            await Task.yield()
        }

        #expect(state.selectedSessionPullRequestURL == expectedURL)
        #expect(!state.isSelectedSessionPullRequestLoading)

        state.selectedSessionID = nil

        #expect(state.selectedSessionPullRequestURL == nil)
        #expect(!state.isSelectedSessionPullRequestLoading)
    }
}
