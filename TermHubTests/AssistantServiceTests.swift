import Foundation
import Testing
@testable import TermHub

@Suite("AssistantService Tests")
struct AssistantServiceTests {

    @Test("buildArguments for Claude first message includes system prompt and tools")
    func claudeFirstMessageArgs() {
        let service = AssistantService()
        let sessionID = UUID()

        let result = service.testBuildArguments(
            text: "hello",
            provider: .claude,
            mcpEnabled: false,
            allowedTools: "WebFetch,mcp__termhub__*",
            isFirstMessage: true,
            sessionID: sessionID
        )

        #expect(result.args.contains("claude"))
        #expect(result.args.contains("--session-id"))
        #expect(result.args.contains(sessionID.uuidString))
        #expect(result.args.contains("--system-prompt"))
        #expect(result.args.contains("--allowedTools"))
        #expect(result.args.contains("WebFetch"))
        #expect(result.args.contains("mcp__termhub__*"))
        #expect(result.args.suffix(2) == ["--", "hello"])
    }

    @Test("buildArguments for Copilot resume ignores wildcard allowed tools")
    func copilotResumeArgs() {
        let service = AssistantService()
        let sessionID = UUID()

        let result = service.testBuildArguments(
            text: "hello",
            provider: .copilot,
            mcpEnabled: false,
            allowedTools: "WebFetch,mcp__termhub__*",
            isFirstMessage: false,
            sessionID: sessionID
        )

        #expect(result.args.starts(with: ["copilot", "-p", "hello"]))
        #expect(result.args.contains("--resume"))
        #expect(result.args.contains(sessionID.uuidString))
        #expect(result.args.contains("--allow-tool"))
        #expect(result.args.contains("WebFetch"))
        #expect(!result.args.contains("mcp__termhub__*"))
        #expect(result.notices.contains { $0.contains("Ignored unsupported Copilot Allowed Tools pattern") })
    }

    @Test("buildArguments for Copilot keeps concrete allowed tools")
    func copilotConcreteToolsArgs() {
        let service = AssistantService()
        let sessionID = UUID()

        let result = service.testBuildArguments(
            text: "hello",
            provider: .copilot,
            mcpEnabled: false,
            allowedTools: "WebFetch,bash",
            isFirstMessage: true,
            sessionID: sessionID
        )

        #expect(result.args.contains("--allow-tool"))
        #expect(result.args.contains("WebFetch"))
        #expect(result.args.contains("bash"))
        #expect(!result.notices.contains { $0.contains("Ignored unsupported Copilot Allowed Tools pattern") })
    }

    @Test("send throws clear error when provider CLI is missing")
    func missingCLIFailsClearly() {
        let service = AssistantService()
        let oldOverride = AssistantService.commandExistsOverride
        AssistantService.commandExistsOverride = { _ in false }
        defer { AssistantService.commandExistsOverride = oldOverride }

        #expect(throws: AssistantService.AssistantServiceError.self) {
            _ = try service.send(
                "test",
                provider: .copilot,
                mcpEnabled: false,
                allowedTools: "",
                workingDirectory: "/tmp"
            )
        }
    }
}
