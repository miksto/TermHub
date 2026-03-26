import Foundation
import Testing

@Suite("MCP Tools Tests")
struct MCPToolsTests {

    // MARK: - errorResult

    @Test("errorResult produces correct structure")
    func errorResultStructure() {
        let result = MCPTools.errorResult("something went wrong")
        guard case .object(let obj) = result else {
            Issue.record("Expected object")
            return
        }
        #expect(obj["isError"] == .bool(true))
        if case .array(let content) = obj["content"],
           case .object(let item) = content.first {
            #expect(item["type"] == .string("text"))
            #expect(item["text"] == .string("something went wrong"))
        } else {
            Issue.record("Expected content array with text item")
        }
    }

    // MARK: - textResult

    @Test("textResult wraps value as JSON text")
    func textResultWrapsValue() {
        let input = JSONValue.object(["key": .string("value")])
        let result = MCPTools.textResult(input)
        guard case .object(let obj) = result,
              case .array(let content) = obj["content"],
              case .object(let item) = content.first,
              let text = item["text"]?.stringValue else {
            Issue.record("Expected content array with text")
            return
        }
        #expect(item["type"] == .string("text"))
        // The text should be valid JSON that can be parsed back
        let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(parsed?.objectValue?["key"]?.stringValue == "value")
    }

    @Test("textResult handles null value")
    func textResultNull() {
        let result = MCPTools.textResult(.null)
        guard case .object(let obj) = result,
              case .array(let content) = obj["content"],
              case .object(let item) = content.first else {
            Issue.record("Expected content structure")
            return
        }
        #expect(item["text"]?.stringValue == "null")
    }

    // MARK: - Tool Definitions

    @Test("allTools contains expected tool names")
    func allToolsContainsExpected() {
        let expectedNames = [
            "list_sessions", "add_session", "remove_session", "select_session", "rename_session",
            "list_folders", "add_folder", "remove_folder",
            "git_status", "git_branches", "git_diff",
            "create_worktree", "send_keys",
            "list_sandboxes", "create_sandbox", "stop_sandbox", "remove_sandbox",
        ]

        let toolNames = MCPTools.allTools.compactMap { tool -> String? in
            tool.objectValue?["name"]?.stringValue
        }

        for expected in expectedNames {
            #expect(toolNames.contains(expected), "Missing tool: \(expected)")
        }
    }

    @Test("each tool has name, description, and inputSchema")
    func allToolsHaveRequiredFields() {
        for tool in MCPTools.allTools {
            guard let obj = tool.objectValue else {
                Issue.record("Tool is not an object")
                continue
            }
            #expect(obj["name"]?.stringValue != nil, "Tool missing name")
            #expect(obj["description"]?.stringValue != nil, "Tool missing description")
            let schema = obj["inputSchema"]?.objectValue
            #expect(schema != nil, "Tool missing inputSchema")
            #expect(schema?["type"]?.stringValue == "object", "inputSchema type should be object")
            #expect(schema?["properties"]?.objectValue != nil, "inputSchema missing properties")
            #expect(schema?["required"]?.arrayValue != nil, "inputSchema missing required")
        }
    }

    @Test("tool required fields are subset of properties")
    func requiredFieldsInProperties() {
        for tool in MCPTools.allTools {
            guard let obj = tool.objectValue,
                  let name = obj["name"]?.stringValue,
                  let schema = obj["inputSchema"]?.objectValue,
                  let properties = schema["properties"]?.objectValue,
                  let required = schema["required"]?.arrayValue else { continue }

            for req in required {
                if let reqName = req.stringValue {
                    #expect(properties[reqName] != nil, "Tool '\(name)' requires '\(reqName)' but it's not in properties")
                }
            }
        }
    }

    // MARK: - call dispatch

    @Test("call returns error for unknown tool")
    func callUnknownTool() {
        let result = MCPTools.call(name: "nonexistent_tool", arguments: [:])
        guard let obj = result.objectValue else {
            Issue.record("Expected object")
            return
        }
        #expect(obj["isError"] == .bool(true))
    }

    @Test("call git_status returns error for missing path param")
    func callGitStatusMissingPath() {
        let result = MCPTools.call(name: "git_status", arguments: [:])
        guard let obj = result.objectValue else {
            Issue.record("Expected object")
            return
        }
        #expect(obj["isError"] == .bool(true))
    }

    @Test("call git_branches returns error for missing repoPath param")
    func callGitBranchesMissingPath() {
        let result = MCPTools.call(name: "git_branches", arguments: [:])
        guard let obj = result.objectValue else {
            Issue.record("Expected object")
            return
        }
        #expect(obj["isError"] == .bool(true))
    }

    @Test("call git_diff returns error for missing path param")
    func callGitDiffMissingPath() {
        let result = MCPTools.call(name: "git_diff", arguments: [:])
        guard let obj = result.objectValue else {
            Issue.record("Expected object")
            return
        }
        #expect(obj["isError"] == .bool(true))
    }

    @Test("call send_keys returns error for missing sessionId")
    func callSendKeysMissingSessionId() {
        let result = MCPTools.call(name: "send_keys", arguments: ["text": .string("hello")])
        guard let obj = result.objectValue else {
            Issue.record("Expected object")
            return
        }
        #expect(obj["isError"] == .bool(true))
    }

    @Test("call send_keys returns error for missing text")
    func callSendKeysMissingText() {
        let result = MCPTools.call(name: "send_keys", arguments: [
            "sessionId": .string("00000000-0000-0000-0000-000000000001"),
        ])
        guard let obj = result.objectValue else {
            Issue.record("Expected object")
            return
        }
        #expect(obj["isError"] == .bool(true))
    }

    @Test("call send_keys returns error for invalid UUID")
    func callSendKeysInvalidUUID() {
        let result = MCPTools.call(name: "send_keys", arguments: [
            "sessionId": .string("not-a-uuid"),
            "text": .string("hello"),
        ])
        guard let obj = result.objectValue else {
            Issue.record("Expected object")
            return
        }
        #expect(obj["isError"] == .bool(true))
    }

    // MARK: - jsonValueToIPCValue / ipcValueToJSONValue

    @Test("jsonValueToIPCValue converts all types correctly")
    func jsonToIPCConversion() {
        let jsonValue = JSONValue.object([
            "str": .string("hello"),
            "num": .int(42),
            "dbl": .double(3.14),
            "flag": .bool(true),
            "nil": .null,
            "arr": .array([.string("a"), .int(1)]),
            "nested": .object(["key": .string("val")]),
        ])

        let ipcValue = MCPTools.testJsonValueToIPCValue(jsonValue)

        guard case .object(let obj) = ipcValue else {
            Issue.record("Expected object")
            return
        }
        #expect(obj["str"] == .string("hello"))
        #expect(obj["num"] == .int(42))
        #expect(obj["dbl"] == .double(3.14))
        #expect(obj["flag"] == .bool(true))
        #expect(obj["nil"] == .null)
        if case .array(let arr) = obj["arr"] {
            #expect(arr.count == 2)
        } else {
            Issue.record("Expected array for 'arr'")
        }
        #expect(obj["nested"]?.objectValue?["key"] == .string("val"))
    }

    @Test("ipcValueToJSONValue converts all types correctly")
    func ipcToJSONConversion() {
        let ipcValue = IPCValue.object([
            "str": .string("world"),
            "num": .int(99),
            "dbl": .double(2.71),
            "flag": .bool(false),
            "nil": .null,
            "arr": .array([.string("b"), .int(2)]),
            "nested": .object(["inner": .string("deep")]),
        ])

        let jsonValue = MCPTools.testIpcValueToJSONValue(ipcValue)

        guard case .object(let obj) = jsonValue else {
            Issue.record("Expected object")
            return
        }
        #expect(obj["str"] == .string("world"))
        #expect(obj["num"] == .int(99))
        #expect(obj["dbl"] == .double(2.71))
        #expect(obj["flag"] == .bool(false))
        #expect(obj["nil"] == .null)
        if case .array(let arr) = obj["arr"] {
            #expect(arr.count == 2)
        } else {
            Issue.record("Expected array for 'arr'")
        }
        #expect(obj["nested"]?.objectValue?["inner"] == .string("deep"))
    }

    @Test("round-trip JSONValue → IPCValue → JSONValue preserves data")
    func jsonIPCRoundTrip() {
        let original = JSONValue.object([
            "sessions": .array([
                .object(["id": .string("abc"), "count": .int(3)]),
            ]),
            "active": .bool(true),
        ])

        let ipc = MCPTools.testJsonValueToIPCValue(original)
        let back = MCPTools.testIpcValueToJSONValue(ipc)
        #expect(back == original)
    }
}
