import Foundation
import Testing

@Suite("MCP Server Tests")
struct MCPServerTests {

    // MARK: - extractMessage

    private func makeMessage(_ json: String) -> Data {
        let body = Data(json.utf8)
        let header = "Content-Length: \(body.count)\r\n\r\n"
        return Data(header.utf8) + body
    }

    @Test("extractMessage parses valid initialize request")
    func extractValidMessage() {
        let json = #"{"jsonrpc":"2.0","method":"initialize","id":1,"params":{}}"#
        let buffer = makeMessage(json)
        let decoder = JSONDecoder()

        let result = extractMessage(from: buffer, decoder: decoder)
        #expect(result != nil)
        let (request, consumed) = result!
        #expect(request.method == "initialize")
        #expect(request.id == .int(1))
        #expect(consumed == buffer.count)
    }

    @Test("extractMessage returns nil for incomplete header")
    func extractIncompleteHeader() {
        let buffer = Data("Content-Length: 50\r\n".utf8) // no second \r\n
        let result = extractMessage(from: buffer, decoder: JSONDecoder())
        #expect(result == nil)
    }

    @Test("extractMessage returns nil for incomplete body")
    func extractIncompleteBody() {
        let header = "Content-Length: 100\r\n\r\n"
        let body = #"{"jsonrpc":"2.0"}"# // only 17 bytes, declared 100
        let buffer = Data(header.utf8) + Data(body.utf8)
        let result = extractMessage(from: buffer, decoder: JSONDecoder())
        #expect(result == nil)
    }

    @Test("extractMessage returns nil for malformed JSON body")
    func extractMalformedJSON() {
        let body = "not valid json!!!"
        let header = "Content-Length: \(body.utf8.count)\r\n\r\n"
        let buffer = Data(header.utf8) + Data(body.utf8)
        let result = extractMessage(from: buffer, decoder: JSONDecoder())
        #expect(result == nil)
    }

    @Test("extractMessage returns nil for empty buffer")
    func extractEmptyBuffer() {
        let result = extractMessage(from: Data(), decoder: JSONDecoder())
        #expect(result == nil)
    }

    @Test("extractMessage returns nil for missing Content-Length header")
    func extractMissingContentLength() {
        let buffer = Data("X-Custom: foo\r\n\r\n{}".utf8)
        let result = extractMessage(from: buffer, decoder: JSONDecoder())
        #expect(result == nil)
    }

    @Test("extractMessage handles Content-Length case-insensitively")
    func extractCaseInsensitiveHeader() {
        let json = #"{"jsonrpc":"2.0","method":"ping","id":1}"#
        let header = "content-length: \(json.utf8.count)\r\n\r\n"
        let buffer = Data(header.utf8) + Data(json.utf8)
        let result = extractMessage(from: buffer, decoder: JSONDecoder())
        #expect(result != nil)
        #expect(result?.0.method == "ping")
    }

    @Test("extractMessage handles multiple headers")
    func extractMultipleHeaders() {
        let json = #"{"jsonrpc":"2.0","method":"ping","id":2}"#
        let header = "X-Custom: bar\r\nContent-Length: \(json.utf8.count)\r\n\r\n"
        let buffer = Data(header.utf8) + Data(json.utf8)
        let result = extractMessage(from: buffer, decoder: JSONDecoder())
        #expect(result != nil)
        #expect(result?.0.method == "ping")
        #expect(result?.0.id == .int(2))
    }

    @Test("extractMessage consumes exact byte count")
    func extractConsumesCorrectBytes() {
        let json = #"{"jsonrpc":"2.0","method":"ping","id":1}"#
        let message = makeMessage(json)
        let trailing = Data("extra-data".utf8)
        let buffer = message + trailing

        let result = extractMessage(from: buffer, decoder: JSONDecoder())
        #expect(result != nil)
        #expect(result?.1 == message.count)
    }

    @Test("extractMessage works with string id")
    func extractStringId() {
        let json = #"{"jsonrpc":"2.0","method":"ping","id":"req-abc"}"#
        let buffer = makeMessage(json)
        let result = extractMessage(from: buffer, decoder: JSONDecoder())
        #expect(result != nil)
        #expect(result?.0.id == .string("req-abc"))
    }

    // MARK: - handleRequest

    @Test("handleRequest returns initialize response")
    func handleInitialize() {
        let request = JSONRPCRequest(jsonrpc: "2.0", id: .int(1), method: "initialize", params: nil)
        let response = handleRequest(request)
        #expect(response != nil)
        #expect(response?.id == .int(1))
        let result = response?.result?.objectValue
        #expect(result?["protocolVersion"]?.stringValue == "2024-11-05")
        #expect(result?["serverInfo"]?.objectValue?["name"]?.stringValue == "termhub")
        #expect(result?["capabilities"]?.objectValue?["tools"] != nil)
    }

    @Test("handleRequest returns nil for notifications/initialized")
    func handleInitializedNotification() {
        let request = JSONRPCRequest(jsonrpc: "2.0", id: nil, method: "notifications/initialized", params: nil)
        let response = handleRequest(request)
        #expect(response == nil)
    }

    @Test("handleRequest returns tools list")
    func handleToolsList() {
        let request = JSONRPCRequest(jsonrpc: "2.0", id: .int(2), method: "tools/list", params: nil)
        let response = handleRequest(request)
        #expect(response != nil)
        #expect(response?.id == .int(2))
        let tools = response?.result?.objectValue?["tools"]?.arrayValue
        #expect(tools != nil)
        #expect((tools?.count ?? 0) > 0)
    }

    @Test("handleRequest returns error for tools/call without tool name")
    func handleToolsCallMissingName() {
        let request = JSONRPCRequest(jsonrpc: "2.0", id: .int(3), method: "tools/call", params: [:])
        let response = handleRequest(request)
        #expect(response != nil)
        #expect(response?.error?.code == -32602)
        #expect(response?.error?.message.contains("Missing tool name") == true)
    }

    @Test("handleRequest returns error for tools/call with nil params")
    func handleToolsCallNilParams() {
        let request = JSONRPCRequest(jsonrpc: "2.0", id: .int(3), method: "tools/call", params: nil)
        let response = handleRequest(request)
        #expect(response != nil)
        #expect(response?.error?.code == -32602)
    }

    @Test("handleRequest responds to ping")
    func handlePing() {
        let request = JSONRPCRequest(jsonrpc: "2.0", id: .int(4), method: "ping", params: nil)
        let response = handleRequest(request)
        #expect(response != nil)
        #expect(response?.id == .int(4))
        #expect(response?.result?.objectValue != nil)
        #expect(response?.error == nil)
    }

    @Test("handleRequest returns method not found for unknown request")
    func handleUnknownMethod() {
        let request = JSONRPCRequest(jsonrpc: "2.0", id: .int(5), method: "unknown/method", params: nil)
        let response = handleRequest(request)
        #expect(response != nil)
        #expect(response?.error?.code == -32601)
        #expect(response?.error?.message.contains("unknown/method") == true)
    }

    @Test("handleRequest returns nil for unknown notification (no id)")
    func handleUnknownNotification() {
        let request = JSONRPCRequest(jsonrpc: "2.0", id: nil, method: "unknown/notification", params: nil)
        let response = handleRequest(request)
        #expect(response == nil)
    }

    @Test("handleRequest preserves string id in response")
    func handlePreservesStringId() {
        let request = JSONRPCRequest(jsonrpc: "2.0", id: .string("abc"), method: "ping", params: nil)
        let response = handleRequest(request)
        #expect(response?.id == .string("abc"))
    }

    @Test("handleRequest tools/call dispatches with arguments")
    func handleToolsCallWithArgs() {
        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .int(6),
            method: "tools/call",
            params: [
                "name": .string("git_status"),
                "arguments": .object(["path": .string("/nonexistent/path")]),
            ]
        )
        let response = handleRequest(request)
        #expect(response != nil)
        #expect(response?.id == .int(6))
        // Should return a result (even if the git command fails, it returns a text result)
        #expect(response?.result != nil)
        #expect(response?.error == nil)
    }

    @Test("handleRequest tools/call with empty arguments object")
    func handleToolsCallEmptyArgs() {
        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .int(7),
            method: "tools/call",
            params: [
                "name": .string("list_sessions"),
                "arguments": .object([:]),
            ]
        )
        let response = handleRequest(request)
        #expect(response != nil)
        #expect(response?.result != nil)
    }

    @Test("handleRequest tools/call with no arguments key")
    func handleToolsCallNoArguments() {
        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .int(8),
            method: "tools/call",
            params: [
                "name": .string("list_sessions"),
            ]
        )
        let response = handleRequest(request)
        #expect(response != nil)
        #expect(response?.result != nil)
    }
}
