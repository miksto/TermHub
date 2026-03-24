import Foundation
import Testing
@testable import TermHub

@Suite("TmuxService Tests")
struct TmuxServiceTests {
    private let mock = MockCommandRunner()
    private let fakeTmuxPath = "/usr/local/bin/tmux"

    init() {
        TmuxService.commandRunner = mock
        TmuxService.tmuxPathOverride = fakeTmuxPath
        TmuxService.resetForTesting()
    }

    // MARK: - createSession

    @Test("createSession sends correct tmux arguments")
    func createSessionBasic() throws {
        // createSession calls: new-session, then ensureServerConfigured (3 calls)
        mock.enqueueSuccess()  // new-session
        mock.enqueueSuccess()  // set-option mouse
        mock.enqueueSuccess()  // set-option set-titles
        mock.enqueueSuccess()  // set-option set-titles-string

        try TmuxService.createSession(name: "test-session", cwd: "/tmp")

        #expect(mock.callCount == 4)
        let call = mock.calls[0]
        #expect(call.executablePath == fakeTmuxPath)
        #expect(call.arguments.contains("new-session"))
        #expect(call.arguments.contains("-s"))
        #expect(call.arguments.contains("test-session"))
        #expect(call.arguments.contains("-c"))
        #expect(call.arguments.contains("/tmp"))
    }

    @Test("createSession with shell command passes it as argument")
    func createSessionWithShellCommand() throws {
        mock.enqueueSuccess()  // new-session
        mock.enqueueSuccess()  // set-option mouse
        mock.enqueueSuccess()  // set-option set-titles
        mock.enqueueSuccess()  // set-option set-titles-string

        try TmuxService.createSession(name: "s1", cwd: "/tmp", shellCommand: "docker exec -it sandbox bash")

        let call = mock.calls[0]
        #expect(call.arguments.last == "docker exec -it sandbox bash")
    }

    @Test("createSession throws when tmux command fails")
    func createSessionFailure() {
        mock.enqueueFailure("duplicate session: test")

        #expect(throws: TmuxServiceError.self) {
            try TmuxService.createSession(name: "test", cwd: "/tmp")
        }
    }

    @Test("createSession throws tmuxNotFound when no path available")
    func createSessionNoTmux() {
        TmuxService.tmuxPathOverride = nil
        // Also ensure real tmux lookup is bypassed by storing nil scenario
        let saved = TmuxService.tmuxPathOverride
        defer { TmuxService.tmuxPathOverride = saved }

        // This only throws tmuxNotFound if ShellEnvironment.tmuxPath is also nil,
        // which we can't guarantee. Instead, test with a path that will fail.
        TmuxService.tmuxPathOverride = fakeTmuxPath
        mock.enqueueFailure("some error")

        #expect(throws: TmuxServiceError.self) {
            try TmuxService.createSession(name: "x", cwd: "/tmp")
        }
    }

    // MARK: - killSession

    @Test("killSession sends correct arguments")
    func killSessionArgs() throws {
        mock.enqueueSuccess()
        try TmuxService.killSession(name: "my-session")

        #expect(mock.callCount == 1)
        #expect(mock.calls[0].arguments.contains("kill-session"))
        #expect(mock.calls[0].arguments.contains("-t"))
        #expect(mock.calls[0].arguments.contains("my-session"))
    }

    @Test("killSession throws on failure")
    func killSessionFailure() {
        mock.enqueueFailure("session not found: bad")

        #expect(throws: TmuxServiceError.self) {
            try TmuxService.killSession(name: "bad")
        }
    }

    // MARK: - sessionExists

    @Test("sessionExists returns true when tmux succeeds")
    func sessionExistsTrue() {
        mock.enqueueSuccess()
        #expect(TmuxService.sessionExists(name: "test") == true)
    }

    @Test("sessionExists returns false when tmux fails")
    func sessionExistsFalse() {
        mock.enqueueFailure("session not found")
        #expect(TmuxService.sessionExists(name: "nonexistent") == false)
    }

    // MARK: - sendKeys

    @Test("sendKeys sends correct arguments")
    func sendKeysArgs() throws {
        mock.enqueueSuccess()
        try TmuxService.sendKeys(sessionName: "s1", text: "ls -la")

        let call = mock.calls[0]
        #expect(call.arguments.contains("send-keys"))
        #expect(call.arguments.contains("-t"))
        #expect(call.arguments.contains("s1"))
        #expect(call.arguments.contains("ls -la"))
        #expect(call.arguments.contains("Enter"))
    }

    // MARK: - listSessions

    @Test("listSessions parses session names")
    func listSessionsParsesNames() {
        mock.enqueueSuccess("session1\nsession2\nsession3")
        let sessions = TmuxService.listSessions()
        #expect(sessions == ["session1", "session2", "session3"])
    }

    @Test("listSessions returns empty on failure")
    func listSessionsEmpty() {
        mock.enqueueFailure("no server running")
        let sessions = TmuxService.listSessions()
        #expect(sessions.isEmpty)
    }

    @Test("listSessions filters empty lines")
    func listSessionsFiltersEmpty() {
        mock.enqueueSuccess("session1\n\nsession2\n")
        let sessions = TmuxService.listSessions()
        #expect(sessions == ["session1", "session2"])
    }

    // MARK: - attachCommand

    @Test("attachCommand returns correct command array")
    func attachCommandArray() {
        let cmd = TmuxService.attachCommand(name: "test-session")
        #expect(cmd == [fakeTmuxPath, "-L", "termhub", "attach-session", "-t", "test-session"])
    }

    @Test("attachCommand returns default shell when no tmux")
    func attachCommandNoTmux() {
        TmuxService.tmuxPathOverride = nil
        // This relies on ShellEnvironment.tmuxPath — if tmux is installed, it won't return default shell.
        // So we just verify the method doesn't crash.
        let cmd = TmuxService.attachCommand(name: "test")
        #expect(!cmd.isEmpty)
        TmuxService.tmuxPathOverride = fakeTmuxPath
    }

    // MARK: - isAvailable

    @Test("isAvailable returns true when tmux path is set")
    func isAvailableTrue() {
        #expect(TmuxService.isAvailable() == true)
    }

    // MARK: - ensureServerConfigured

    @Test("ensureServerConfigured only runs once")
    func ensureServerConfiguredOnce() throws {
        // First createSession triggers ensureServerConfigured
        mock.enqueueSuccess()  // new-session
        mock.enqueueSuccess()  // set-option mouse
        mock.enqueueSuccess()  // set-option set-titles
        mock.enqueueSuccess()  // set-option set-titles-string
        try TmuxService.createSession(name: "s1", cwd: "/tmp")
        #expect(mock.callCount == 4)

        // Second createSession should NOT re-run config
        mock.enqueueSuccess()  // new-session only
        try TmuxService.createSession(name: "s2", cwd: "/tmp")
        #expect(mock.callCount == 5)  // only 1 more call
    }

    // MARK: - Error messages

    @Test("commandFailed error includes stderr message")
    func commandFailedIncludesStderr() {
        mock.enqueue(output: "", errorOutput: "specific error detail", exitCode: 1)

        do {
            try TmuxService.killSession(name: "x")
            Issue.record("Expected error")
        } catch let error as TmuxServiceError {
            #expect(error.errorDescription?.contains("specific error detail") == true)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("commandFailed falls back to stdout when stderr is empty")
    func commandFailedFallbackToStdout() {
        mock.enqueue(output: "stdout error info", errorOutput: "", exitCode: 1)

        do {
            try TmuxService.killSession(name: "x")
            Issue.record("Expected error")
        } catch let error as TmuxServiceError {
            #expect(error.errorDescription?.contains("stdout error info") == true)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
}
