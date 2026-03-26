import Foundation
import Testing

@Suite("MCP Protocol Tests")
struct MCPProtocolTests {

    // MARK: - JSONRPCId

    @Test("JSONRPCId decodes integer")
    func idDecodesInt() throws {
        let data = Data("1".utf8)
        let id = try JSONDecoder().decode(JSONRPCId.self, from: data)
        #expect(id == .int(1))
    }

    @Test("JSONRPCId decodes string")
    func idDecodesString() throws {
        let data = Data(#""abc-123""#.utf8)
        let id = try JSONDecoder().decode(JSONRPCId.self, from: data)
        #expect(id == .string("abc-123"))
    }

    @Test("JSONRPCId int round-trips")
    func idIntRoundTrip() throws {
        let original = JSONRPCId.int(42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONRPCId.self, from: data)
        #expect(decoded == original)
    }

    @Test("JSONRPCId string round-trips")
    func idStringRoundTrip() throws {
        let original = JSONRPCId.string("req-1")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONRPCId.self, from: data)
        #expect(decoded == original)
    }

    @Test("JSONRPCId rejects boolean")
    func idRejectsBoolean() {
        let data = Data("true".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(JSONRPCId.self, from: data)
        }
    }

    // MARK: - JSONValue encoding/decoding

    @Test("JSONValue string round-trips")
    func stringRoundTrip() throws {
        let value = JSONValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded.stringValue == "hello")
    }

    @Test("JSONValue int round-trips")
    func intRoundTrip() throws {
        let value = JSONValue.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("JSONValue double round-trips")
    func doubleRoundTrip() throws {
        let value = JSONValue.double(3.14)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("JSONValue bool round-trips")
    func boolRoundTrip() throws {
        let value = JSONValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("JSONValue null round-trips")
    func nullRoundTrip() throws {
        let value = JSONValue.null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("JSONValue array round-trips")
    func arrayRoundTrip() throws {
        let value = JSONValue.array([.string("a"), .int(1), .bool(false)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded.arrayValue?.count == 3)
    }

    @Test("JSONValue object round-trips")
    func objectRoundTrip() throws {
        let value = JSONValue.object(["key": .string("val"), "num": .int(5)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded.objectValue?["key"]?.stringValue == "val")
    }

    @Test("JSONValue nested structure round-trips")
    func nestedRoundTrip() throws {
        let value = JSONValue.object([
            "items": .array([
                .object(["id": .int(1), "name": .string("first")]),
                .object(["id": .int(2), "name": .string("second")]),
            ]),
            "total": .int(2),
            "meta": .null,
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("JSONValue accessors return nil for mismatched types")
    func accessorMismatch() {
        let str = JSONValue.string("hello")
        #expect(str.objectValue == nil)
        #expect(str.arrayValue == nil)

        let num = JSONValue.int(42)
        #expect(num.stringValue == nil)
        #expect(num.objectValue == nil)
        #expect(num.arrayValue == nil)

        let arr = JSONValue.array([])
        #expect(arr.stringValue == nil)
        #expect(arr.objectValue == nil)
    }

    // MARK: - JSONRPCRequest

    @Test("JSONRPCRequest decodes initialize request")
    func decodeInitialize() throws {
        let json = #"{"jsonrpc":"2.0","method":"initialize","id":1,"params":{}}"#
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        #expect(request.jsonrpc == "2.0")
        #expect(request.method == "initialize")
        #expect(request.id == .int(1))
        #expect(request.params != nil)
    }

    @Test("JSONRPCRequest decodes notification without id")
    func decodeNotification() throws {
        let json = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        #expect(request.method == "notifications/initialized")
        #expect(request.id == nil)
        #expect(request.params == nil)
    }

    @Test("JSONRPCRequest decodes tools/call with arguments")
    func decodeToolsCall() throws {
        let json = #"{"jsonrpc":"2.0","method":"tools/call","id":"req-1","params":{"name":"list_sessions","arguments":{}}}"#
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        #expect(request.method == "tools/call")
        #expect(request.id == .string("req-1"))
        #expect(request.params?["name"]?.stringValue == "list_sessions")
    }

    // MARK: - JSONRPCResponse

    @Test("JSONRPCResponse result encoding")
    func encodeResult() throws {
        let response = JSONRPCResponse.result(.object(["key": .string("value")]), id: .int(1))
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .int(1))
        #expect(decoded.result?.objectValue?["key"]?.stringValue == "value")
        #expect(decoded.error == nil)
    }

    @Test("JSONRPCResponse error encoding")
    func encodeError() throws {
        let response = JSONRPCResponse.error(code: -32601, message: "Method not found", id: .int(1))
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .int(1))
        #expect(decoded.result == nil)
        #expect(decoded.error?.code == -32601)
        #expect(decoded.error?.message == "Method not found")
    }

    @Test("JSONRPCResponse with nil id")
    func encodeNilId() throws {
        let response = JSONRPCResponse.result(.string("ok"), id: nil)
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        #expect(decoded.id == nil)
    }
}
