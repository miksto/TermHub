import Testing
@testable import MuxManager

@Suite("TerminalSession Tests")
struct TerminalSessionTests {
    @Test("plain shell tmuxSessionName uses folder name")
    func plainShellTmuxName() {
        let session = TerminalSession(
            folderID: UUID(),
            title: "my-repo",
            workingDirectory: "/Users/dev/my-repo"
        )
        #expect(session.tmuxSessionName == "mux-my-repo")
    }

    @Test("worktree tmuxSessionName includes sanitized branch")
    func worktreeTmuxName() {
        let session = TerminalSession(
            folderID: UUID(),
            title: "feature branch",
            workingDirectory: "/Users/dev/my-repo",
            worktreePath: "/Users/dev/my-repo-feature-login",
            branchName: "feature/login"
        )
        #expect(session.tmuxSessionName == "mux-my-repo-feature-login")
    }

    @Test("worktree tmuxSessionName with nested slashes")
    func worktreeNestedSlashes() {
        let session = TerminalSession(
            folderID: UUID(),
            title: "nested branch",
            workingDirectory: "/Users/dev/project",
            worktreePath: "/Users/dev/project-fix-ui-button",
            branchName: "fix/ui/button"
        )
        #expect(session.tmuxSessionName == "mux-project-fix-ui-button")
    }

    @Test("explicit tmuxSessionName overrides generated one")
    func explicitTmuxName() {
        let session = TerminalSession(
            folderID: UUID(),
            title: "test",
            workingDirectory: "/Users/dev/repo",
            tmuxSessionName: "custom-name"
        )
        #expect(session.tmuxSessionName == "custom-name")
    }

    @Test("generateTmuxSessionName static helper")
    func generateHelper() {
        let plain = TerminalSession.generateTmuxSessionName(
            workingDirectory: "/Users/dev/app",
            branchName: nil
        )
        #expect(plain == "mux-app")

        let worktree = TerminalSession.generateTmuxSessionName(
            workingDirectory: "/Users/dev/app",
            branchName: "release/v2.0"
        )
        #expect(worktree == "mux-app-release-v2.0")
    }

    @Test("Codable round-trip preserves all fields including optionals")
    func codableRoundTrip() throws {
        let original = TerminalSession(
            folderID: UUID(),
            title: "Test Session",
            workingDirectory: "/Users/dev/repo",
            worktreePath: "/Users/dev/repo-feature",
            branchName: "feature/test"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.folderID == original.folderID)
        #expect(decoded.title == original.title)
        #expect(decoded.workingDirectory == original.workingDirectory)
        #expect(decoded.worktreePath == original.worktreePath)
        #expect(decoded.branchName == original.branchName)
        #expect(decoded.tmuxSessionName == original.tmuxSessionName)
    }

    @Test("Codable round-trip with nil optionals")
    func codableRoundTripNilOptionals() throws {
        let original = TerminalSession(
            folderID: UUID(),
            title: "Plain Session",
            workingDirectory: "/Users/dev/repo"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)

        #expect(decoded.worktreePath == nil)
        #expect(decoded.branchName == nil)
        #expect(decoded.tmuxSessionName == "mux-repo")
    }
}
