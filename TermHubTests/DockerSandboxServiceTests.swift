import Foundation
import Testing
@testable import TermHub

@Suite("DockerSandboxService Tests")
struct DockerSandboxServiceTests {
    private let mock = MockCommandRunner()
    private let fakeDockerPath = "/usr/local/bin/docker"

    init() {
        DockerSandboxService.commandRunner = mock
        DockerSandboxService.dockerPathOverride = fakeDockerPath
    }

    // MARK: - isValidSandboxName

    @Test("isValidSandboxName accepts valid names")
    func validNames() {
        #expect(DockerSandboxService.isValidSandboxName("my-sandbox") == true)
        #expect(DockerSandboxService.isValidSandboxName("test123") == true)
        #expect(DockerSandboxService.isValidSandboxName("My.Sandbox_v2") == true)
        #expect(DockerSandboxService.isValidSandboxName("a") == true)
    }

    @Test("isValidSandboxName rejects invalid names")
    func invalidNames() {
        #expect(DockerSandboxService.isValidSandboxName("") == false)
        #expect(DockerSandboxService.isValidSandboxName("-starts-with-dash") == false)
        #expect(DockerSandboxService.isValidSandboxName(".starts-with-dot") == false)
        #expect(DockerSandboxService.isValidSandboxName("_starts-with-underscore") == false)
        #expect(DockerSandboxService.isValidSandboxName("has spaces") == false)
        #expect(DockerSandboxService.isValidSandboxName("has/slash") == false)
        #expect(DockerSandboxService.isValidSandboxName("has@special") == false)
    }

    // MARK: - execCommand

    @Test("execCommand generates correct docker command")
    func execCommandBasic() {
        let cmd = DockerSandboxService.execCommand(sandboxName: "test-sb", cwd: "/home/user/project")
        #expect(cmd.contains("docker sandbox exec -it test-sb"))
        #expect(cmd.contains("cd /home/user/project"))
    }

    @Test("execCommand escapes single quotes in cwd")
    func execCommandEscapesSingleQuotes() {
        let cmd = DockerSandboxService.execCommand(sandboxName: "sb", cwd: "/home/user/project's dir")
        #expect(cmd.contains("'\\''"))
    }

    @Test("execCommand returns error message for invalid sandbox name")
    func execCommandInvalidName() {
        let cmd = DockerSandboxService.execCommand(sandboxName: "-bad", cwd: "/tmp")
        #expect(cmd.contains("Invalid sandbox name"))
    }

    @Test("execCommand returns error when docker not found")
    func execCommandNoDocker() {
        DockerSandboxService.dockerPathOverride = nil
        let savedPath = DockerSandboxService.dockerPath
        // If docker is not installed, resolvedDockerPath will be nil
        if savedPath == nil {
            let cmd = DockerSandboxService.execCommand(sandboxName: "test", cwd: "/tmp")
            #expect(cmd.contains("docker not found"))
        }
        DockerSandboxService.dockerPathOverride = fakeDockerPath
    }

    // MARK: - listSandboxes

    @Test("listSandboxes parses JSON response")
    func listSandboxesParsesJSON() {
        let json = """
        {"vms":[{"name":"sb1","agent":"claude","status":"running","workspaces":["/tmp/project"]},{"name":"sb2","agent":"copilot","status":"stopped","workspaces":[]}]}
        """
        mock.enqueueSuccess(json)

        let sandboxes = DockerSandboxService.listSandboxes()
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
        mock.enqueueFailure("docker not running")
        let sandboxes = DockerSandboxService.listSandboxes()
        #expect(sandboxes.isEmpty)
    }

    @Test("listSandboxes returns empty for malformed JSON")
    func listSandboxesMalformedJSON() {
        mock.enqueueSuccess("not json at all")
        let sandboxes = DockerSandboxService.listSandboxes()
        #expect(sandboxes.isEmpty)
    }

    @Test("listSandboxes sends correct arguments")
    func listSandboxesArgs() {
        mock.enqueueSuccess("{\"vms\":[]}")
        _ = DockerSandboxService.listSandboxes()

        let call = mock.lastCall!
        #expect(call.executablePath == fakeDockerPath)
        #expect(call.arguments == ["sandbox", "ls", "--json"])
    }

    // MARK: - createSandbox

    @Test("createSandbox sends correct arguments")
    func createSandboxArgs() throws {
        mock.enqueueSuccess()
        try DockerSandboxService.createSandbox(name: "test-sb", agent: "claude", workspaces: ["/tmp/p1", "/tmp/p2"])

        let call = mock.lastCall!
        #expect(call.arguments == ["sandbox", "create", "--name", "test-sb", "claude", "/tmp/p1", "/tmp/p2"])
    }

    @Test("createSandbox throws on failure")
    func createSandboxFailure() {
        mock.enqueueFailure("name already in use")

        #expect(throws: DockerSandboxError.self) {
            try DockerSandboxService.createSandbox(name: "dup", workspaces: ["/tmp"])
        }
    }

    @Test("createSandbox throws dockerNotFound when no path")
    func createSandboxNoDocker() {
        DockerSandboxService.dockerPathOverride = nil
        let savedPath = DockerSandboxService.dockerPath
        if savedPath == nil {
            #expect {
                try DockerSandboxService.createSandbox(name: "x", workspaces: ["/tmp"])
            } throws: { error in
                (error as? DockerSandboxError) == .dockerNotFound
            }
        }
        DockerSandboxService.dockerPathOverride = fakeDockerPath
    }

    // MARK: - stopSandbox

    @Test("stopSandbox sends correct arguments")
    func stopSandboxArgs() throws {
        mock.enqueueSuccess()
        try DockerSandboxService.stopSandbox(name: "my-sb")

        let call = mock.lastCall!
        #expect(call.arguments == ["sandbox", "stop", "my-sb"])
    }

    @Test("stopSandbox throws on failure")
    func stopSandboxFailure() {
        mock.enqueueFailure("sandbox not found")

        #expect(throws: DockerSandboxError.self) {
            try DockerSandboxService.stopSandbox(name: "missing")
        }
    }

    // MARK: - removeSandbox

    @Test("removeSandbox sends correct arguments")
    func removeSandboxArgs() throws {
        mock.enqueueSuccess()
        try DockerSandboxService.removeSandbox(name: "old-sb")

        let call = mock.lastCall!
        #expect(call.arguments == ["sandbox", "rm", "old-sb"])
    }

    @Test("removeSandbox throws on failure")
    func removeSandboxFailure() {
        mock.enqueueFailure("cannot remove running sandbox")

        #expect(throws: DockerSandboxError.self) {
            try DockerSandboxService.removeSandbox(name: "running-sb")
        }
    }

    // MARK: - Error messages

    @Test("commandFailed error includes message")
    func commandFailedMessage() {
        mock.enqueue(output: "", errorOutput: "specific docker error", exitCode: 1)

        do {
            try DockerSandboxService.stopSandbox(name: "x")
            Issue.record("Expected error")
        } catch let error as DockerSandboxError {
            #expect(error.errorDescription?.contains("specific docker error") == true)
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
}
