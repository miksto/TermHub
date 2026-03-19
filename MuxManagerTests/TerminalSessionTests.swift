import Foundation
import Testing
@testable import MuxManager

@Suite("TerminalSession Tests")
struct TerminalSessionTests {
    @Test("plain shell tmuxSessionName uses folder name with UUID suffix")
    func plainShellTmuxName() {
        let id = UUID()
        let session = TerminalSession(
            id: id,
            folderID: UUID(),
            title: "my-repo",
            workingDirectory: "/Users/dev/my-repo"
        )
        let shortID = String(id.uuidString.prefix(4)).lowercased()
        #expect(session.tmuxSessionName == "mux-my-repo-\(shortID)")
    }

    @Test("worktree tmuxSessionName includes sanitized branch and UUID suffix")
    func worktreeTmuxName() {
        let id = UUID()
        let session = TerminalSession(
            id: id,
            folderID: UUID(),
            title: "feature branch",
            workingDirectory: "/Users/dev/my-repo",
            worktreePath: "/Users/dev/my-repo-feature-login",
            branchName: "feature/login"
        )
        let shortID = String(id.uuidString.prefix(4)).lowercased()
        #expect(session.tmuxSessionName == "mux-my-repo-feature-login-\(shortID)")
    }

    @Test("worktree tmuxSessionName with nested slashes")
    func worktreeNestedSlashes() {
        let id = UUID()
        let session = TerminalSession(
            id: id,
            folderID: UUID(),
            title: "nested branch",
            workingDirectory: "/Users/dev/project",
            worktreePath: "/Users/dev/project-fix-ui-button",
            branchName: "fix/ui/button"
        )
        let shortID = String(id.uuidString.prefix(4)).lowercased()
        #expect(session.tmuxSessionName == "mux-project-fix-ui-button-\(shortID)")
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

    @Test("generateTmuxSessionName static helper with id parameter")
    func generateHelper() {
        let id = UUID()
        let shortID = String(id.uuidString.prefix(4)).lowercased()

        let plain = TerminalSession.generateTmuxSessionName(
            workingDirectory: "/Users/dev/app",
            branchName: nil,
            id: id
        )
        #expect(plain == "mux-app-\(shortID)")

        let worktree = TerminalSession.generateTmuxSessionName(
            workingDirectory: "/Users/dev/app",
            branchName: "release/v2.0",
            id: id
        )
        #expect(worktree == "mux-app-release-v2.0-\(shortID)")
    }

    @Test("two sessions with same folder name get different tmux names")
    func uniqueTmuxNamesForSameFolder() {
        let session1 = TerminalSession(
            folderID: UUID(),
            title: "app1",
            workingDirectory: "/projects/app"
        )
        let session2 = TerminalSession(
            folderID: UUID(),
            title: "app2",
            workingDirectory: "/work/app"
        )
        #expect(session1.tmuxSessionName != session2.tmuxSessionName)
        #expect(session1.tmuxSessionName.hasPrefix("mux-app-"))
        #expect(session2.tmuxSessionName.hasPrefix("mux-app-"))
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
        let id = UUID()
        let original = TerminalSession(
            id: id,
            folderID: UUID(),
            title: "Plain Session",
            workingDirectory: "/Users/dev/repo"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)

        #expect(decoded.worktreePath == nil)
        #expect(decoded.branchName == nil)
        let shortID = String(id.uuidString.prefix(4)).lowercased()
        #expect(decoded.tmuxSessionName == "mux-repo-\(shortID)")
    }
}
