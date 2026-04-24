import Foundation
import Testing
@testable import TermHub

@Suite("SbxService Tests")
struct SbxServiceTests {
    private let mock = MockCommandRunner()
    private let fakeSbxPath = "/usr/local/bin/sbx"

    init() {
        SbxService.commandRunner = mock
        SbxService.sbxPathOverride = fakeSbxPath
    }

    // MARK: - isValidSandboxName

    @Test("isValidSandboxName accepts valid names")
    func validNames() {
        #expect(SbxService.isValidSandboxName("my-sandbox") == true)
        #expect(SbxService.isValidSandboxName("test123") == true)
        #expect(SbxService.isValidSandboxName("My.Sandbox_v2") == true)
        #expect(SbxService.isValidSandboxName("a") == true)
    }

    @Test("isValidSandboxName rejects invalid names")
    func invalidNames() {
        #expect(SbxService.isValidSandboxName("") == false)
        #expect(SbxService.isValidSandboxName("-starts-with-dash") == false)
        #expect(SbxService.isValidSandboxName(".starts-with-dot") == false)
        #expect(SbxService.isValidSandboxName("_starts-with-underscore") == false)
        #expect(SbxService.isValidSandboxName("has spaces") == false)
        #expect(SbxService.isValidSandboxName("has/slash") == false)
        #expect(SbxService.isValidSandboxName("has@special") == false)
    }

    // MARK: - execCommand

    @Test("execCommand generates correct sbx command")
    func execCommandBasic() {
        let cmd = SbxService.execCommand(sandboxName: "test-sb", cwd: "/home/user/project")
        #expect(cmd.contains("-e 'TERM=xterm-256color'"))
        #expect(cmd.contains("-it test-sb"))
        #expect(cmd.contains("cd /home/user/project"))
    }

    @Test("execCommand escapes single quotes in cwd")
    func execCommandEscapesCwd() {
        let cmd = SbxService.execCommand(sandboxName: "sb", cwd: "/home/user/project's dir")
        #expect(cmd.contains("'\\''"))
    }

    @Test("execCommand returns error message for invalid sandbox name")
    func execCommandInvalidName() {
        let cmd = SbxService.execCommand(sandboxName: "-bad", cwd: "/tmp")
        #expect(cmd.contains("Invalid sandbox name"))
    }

    @Test("execCommand returns error when sbx not found")
    func execCommandNoSbx() {
        SbxService.sbxPathOverride = nil
        let savedPath = SbxService.sbxPath
        // If sbx is not installed, resolvedSbxPath will be nil
        if savedPath == nil {
            let cmd = SbxService.execCommand(sandboxName: "test", cwd: "/tmp")
            #expect(cmd.contains("sbx not found"))
        }
        SbxService.sbxPathOverride = fakeSbxPath
    }

    // MARK: - isValidEnvVarKey

    @Test("isValidEnvVarKey accepts valid keys")
    func validEnvVarKeys() {
        #expect(SbxService.isValidEnvVarKey("HOME") == true)
        #expect(SbxService.isValidEnvVarKey("NODE_ENV") == true)
        #expect(SbxService.isValidEnvVarKey("_PRIVATE") == true)
        #expect(SbxService.isValidEnvVarKey("a") == true)
        #expect(SbxService.isValidEnvVarKey("PATH123") == true)
    }

    @Test("isValidEnvVarKey rejects invalid keys")
    func invalidEnvVarKeys() {
        #expect(SbxService.isValidEnvVarKey("") == false)
        #expect(SbxService.isValidEnvVarKey("123BAD") == false)
        #expect(SbxService.isValidEnvVarKey("has-dash") == false)
        #expect(SbxService.isValidEnvVarKey("has space") == false)
        #expect(SbxService.isValidEnvVarKey("has.dot") == false)
    }

    // MARK: - execCommand with environment variables

    @Test("execCommand includes environment variable flags")
    func execCommandWithEnvVars() {
        let cmd = SbxService.execCommand(
            sandboxName: "test-sb",
            cwd: "/home/user/project",
            environmentVariables: ["NODE_ENV": "development", "DEBUG": "true"]
        )
        #expect(cmd.contains("-e 'DEBUG=true'"))
        #expect(cmd.contains("-e 'NODE_ENV=development'"))
        #expect(cmd.contains("exec -e"))
        #expect(cmd.contains("-it test-sb"))
    }

    @Test("execCommand escapes single quotes in env var values")
    func execCommandEnvVarEscaping() {
        let cmd = SbxService.execCommand(
            sandboxName: "sb",
            cwd: "/tmp",
            environmentVariables: ["MSG": "it's working"]
        )
        #expect(cmd.contains("-e 'MSG=it'\\''s working'"))
    }

    @Test("execCommand skips invalid env var keys")
    func execCommandInvalidEnvKey() {
        let cmd = SbxService.execCommand(
            sandboxName: "sb",
            cwd: "/tmp",
            environmentVariables: ["VALID_KEY": "ok", "invalid-key": "skip", "123bad": "skip"]
        )
        #expect(cmd.contains("VALID_KEY"))
        #expect(!cmd.contains("invalid-key"))
        #expect(!cmd.contains("123bad"))
    }

    @Test("execCommand with empty env vars still includes TERM")
    func execCommandEmptyEnvVars() {
        let cmd = SbxService.execCommand(sandboxName: "test-sb", cwd: "/tmp", environmentVariables: [:])
        #expect(cmd.contains("-e 'TERM=xterm-256color'"))
        #expect(cmd.contains("-it test-sb"))
    }

    // MARK: - listSandboxes

    @Test("listSandboxes parses JSON response")
    func listSandboxesParsesJSON() {
        let json = """
        {"sandboxes":[{"name":"sb1","agent":"claude","status":"running","workspaces":["/tmp/project"]},{"name":"sb2","agent":"copilot","status":"stopped","workspaces":[]}]}
        """
        mock.enqueueSuccess(json)

        let sandboxes = SbxService.listSandboxes()
        #expect(sandboxes.count == 2)
        #expect(sandboxes[0].name == "sb1")
        #expect(sandboxes[0].isRunning == true)
        #expect(sandboxes[0].agent == "claude")
        #expect(sandboxes[0].workspaces == ["/tmp/project"])
        #expect(sandboxes[1].name == "sb2")
        #expect(sandboxes[1].isStopped == true)
    }

    @Test("listSandboxes returns empty on failure")
    func listSandboxesFailure() {
        mock.enqueueFailure("sbx not running")
        let sandboxes = SbxService.listSandboxes()
        #expect(sandboxes.isEmpty)
    }

    @Test("listSandboxes returns empty for malformed JSON")
    func listSandboxesMalformedJSON() {
        mock.enqueueSuccess("not json at all")
        let sandboxes = SbxService.listSandboxes()
        #expect(sandboxes.isEmpty)
    }

    @Test("listSandboxes sends correct arguments")
    func listSandboxesArgs() {
        mock.enqueueSuccess("{\"sandboxes\":[]}")
        _ = SbxService.listSandboxes()

        let call = mock.lastCall!
        #expect(call.executablePath == fakeSbxPath)
        #expect(call.arguments == ["ls", "--json"])
    }

    // MARK: - createSandbox

    @Test("createSandbox sends correct arguments")
    func createSandboxArgs() throws {
        mock.enqueueSuccess()
        try SbxService.createSandbox(name: "test-sb", agent: "claude", workspaces: ["/tmp/p1", "/tmp/p2"])

        let call = mock.lastCall!
        #expect(call.arguments == ["create", "--name", "test-sb", "claude", "/tmp/p1", "/tmp/p2"])
    }

    @Test("createSandbox throws on failure")
    func createSandboxFailure() {
        mock.enqueueFailure("name already in use")

        #expect(throws: SbxError.self) {
            try SbxService.createSandbox(name: "dup", workspaces: ["/tmp"])
        }
    }

    @Test("createSandbox throws sbxNotFound when no path")
    func createSandboxNoSbx() {
        SbxService.sbxPathOverride = nil
        let savedPath = SbxService.sbxPath
        if savedPath == nil {
            #expect {
                try SbxService.createSandbox(name: "x", workspaces: ["/tmp"])
            } throws: { error in
                (error as? SbxError) == .sbxNotFound
            }
        }
        SbxService.sbxPathOverride = fakeSbxPath
    }

    // MARK: - stopSandbox

    @Test("stopSandbox sends correct arguments")
    func stopSandboxArgs() throws {
        mock.enqueueSuccess()
        try SbxService.stopSandbox(name: "my-sb")

        let call = mock.lastCall!
        #expect(call.arguments == ["stop", "my-sb"])
    }

    @Test("stopSandbox throws on failure")
    func stopSandboxFailure() {
        mock.enqueueFailure("sandbox not found")

        #expect(throws: SbxError.self) {
            try SbxService.stopSandbox(name: "missing")
        }
    }

    // MARK: - removeSandbox

    @Test("removeSandbox sends correct arguments")
    func removeSandboxArgs() throws {
        mock.enqueueSuccess()
        try SbxService.removeSandbox(name: "old-sb")

        let call = mock.lastCall!
        #expect(call.arguments == ["rm", "old-sb"])
    }

    @Test("removeSandbox throws on failure")
    func removeSandboxFailure() {
        mock.enqueueFailure("cannot remove running sandbox")

        #expect(throws: SbxError.self) {
            try SbxService.removeSandbox(name: "running-sb")
        }
    }

    // MARK: - Error messages

    @Test("commandFailed error includes message")
    func commandFailedMessage() {
        mock.enqueue(output: "", errorOutput: "specific sbx error", exitCode: 1)

        do {
            try SbxService.stopSandbox(name: "x")
            Issue.record("Expected error")
        } catch let error as SbxError {
            #expect(error.errorDescription?.contains("specific sbx error") == true)
        } catch {
            Issue.record("Wrong error type")
        }
    }

    // MARK: - SandboxAgent

    @Test("SandboxAgent displayNames are non-empty")
    func sandboxAgentDisplayNames() {
        for agent in SandboxAgent.allCases {
            #expect(!agent.displayName.isEmpty)
        }
    }

    @Test("SandboxAgent rawValues are distinct")
    func sandboxAgentRawValues() {
        let values = SandboxAgent.allCases.map(\.rawValue)
        #expect(Set(values).count == values.count)
    }

    // MARK: - SandboxInfo

    @Test("SandboxInfo isRunning and isStopped computed properties")
    func sandboxInfoStatus() {
        let running = SandboxInfo(name: "a", agent: "claude", status: "running", workspaces: [])
        #expect(running.isRunning == true)
        #expect(running.isStopped == false)

        let stopped = SandboxInfo(name: "b", agent: "claude", status: "stopped", workspaces: [])
        #expect(stopped.isRunning == false)
        #expect(stopped.isStopped == true)

        let other = SandboxInfo(name: "c", agent: "claude", status: "creating", workspaces: [])
        #expect(other.isRunning == false)
        #expect(other.isStopped == false)
    }

    @Test("SandboxInfo decodes from JSON with missing optional fields")
    func sandboxInfoDecodesPartial() throws {
        let json = """
        {"name": "test", "status": "running"}
        """
        let data = json.data(using: .utf8)!
        let info = try JSONDecoder().decode(SandboxInfo.self, from: data)
        #expect(info.name == "test")
        #expect(info.agent == "")
        #expect(info.workspaces.isEmpty)
    }

    // MARK: - SandboxAgent.autoLaunchCommand

    @Test("autoLaunchCommand returns correct commands for each agent")
    func autoLaunchCommands() {
        #expect(SandboxAgent.claude.autoLaunchCommand == "claude --dangerously-skip-permissions")
        #expect(SandboxAgent.copilot.autoLaunchCommand == "copilot --allow-all --autopilot")
        #expect(SandboxAgent.codex.autoLaunchCommand == "codex --full-auto")
        #expect(SandboxAgent.gemini.autoLaunchCommand == "gemini --yolo")
        #expect(SandboxAgent.kiro.autoLaunchCommand == "kiro")
        #expect(SandboxAgent.opencode.autoLaunchCommand == "opencode")
    }

    @Test("autoLaunchCommand returns nil for shell and docker-agent")
    func autoLaunchCommandNilCases() {
        #expect(SandboxAgent.shell.autoLaunchCommand == nil)
        #expect(SandboxAgent.dockerAgent.autoLaunchCommand == nil)
    }
}
