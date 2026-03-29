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

    @Test("buildArguments for Copilot MCP config uses stdio schema")
    func copilotMCPConfigUsesStdioSchema() {
        let service = AssistantService()
        let sessionID = UUID()

        let result = service.testBuildArguments(
            text: "hello",
            provider: .copilot,
            mcpEnabled: true,
            allowedTools: "WebFetch",
            isFirstMessage: true,
            sessionID: sessionID
        )

        guard let flagIndex = result.args.firstIndex(of: "--additional-mcp-config"),
              result.args.indices.contains(flagIndex + 1)
        else {
            Issue.record("Expected --additional-mcp-config argument")
            return
        }

        let config = result.args[flagIndex + 1]
        #expect(config.contains("\"termhub\""))
        #expect(config.contains("\"type\":\"stdio\""))
        #expect(config.contains("\"args\":[]"))
    }

    @Test("buildArguments for Claude includes custom model and effort")
    func claudeCustomModelAndEffort() {
        let service = AssistantService()
        let sessionID = UUID()

        let result = service.testBuildArguments(
            text: "hello",
            provider: .claude,
            mcpEnabled: false,
            allowedTools: "",
            model: "opus",
            effort: "high",
            isFirstMessage: true,
            sessionID: sessionID
        )

        #expect(result.args.contains("--model"))
        #expect(result.args.contains("opus"))
        #expect(result.args.contains("--effort"))
        #expect(result.args.contains("high"))
    }

    @Test("buildArguments for Claude omits model and effort when empty")
    func claudeOmitsModelAndEffortWhenEmpty() {
        let service = AssistantService()
        let sessionID = UUID()

        let result = service.testBuildArguments(
            text: "hello",
            provider: .claude,
            mcpEnabled: false,
            allowedTools: "",
            model: "",
            effort: "",
            isFirstMessage: true,
            sessionID: sessionID
        )

        #expect(!result.args.contains("--model"))
        #expect(!result.args.contains("--effort"))
    }

    @Test("buildArguments for Copilot includes custom model and uses --reasoning-effort")
    func copilotCustomModelAndEffort() {
        let service = AssistantService()
        let sessionID = UUID()

        let result = service.testBuildArguments(
            text: "hello",
            provider: .copilot,
            mcpEnabled: false,
            allowedTools: "",
            model: "gpt-5.2",
            effort: "medium",
            isFirstMessage: true,
            sessionID: sessionID
        )

        #expect(result.args.contains("--model"))
        #expect(result.args.contains("gpt-5.2"))
        #expect(result.args.contains("--reasoning-effort"))
        #expect(result.args.contains("medium"))
        #expect(!result.args.contains("--effort"))
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
