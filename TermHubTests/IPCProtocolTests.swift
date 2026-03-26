import Foundation
import Testing
@testable import TermHub

@Suite("IPCProtocol Tests")
struct IPCProtocolTests {

    // MARK: - IPCValue round-trip encoding

    @Test("IPCValue string round-trips through JSON")
    func stringRoundTrip() throws {
        let value = IPCValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(IPCValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded.stringValue == "hello")
    }

    @Test("IPCValue int round-trips through JSON")
    func intRoundTrip() throws {
        let value = IPCValue.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(IPCValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded.intValue == 42)
    }

    @Test("IPCValue bool round-trips through JSON")
    func boolRoundTrip() throws {
        let value = IPCValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(IPCValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded.boolValue == true)
    }

    @Test("IPCValue null round-trips through JSON")
    func nullRoundTrip() throws {
        let value = IPCValue.null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(IPCValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("IPCValue array round-trips through JSON")
    func arrayRoundTrip() throws {
        let value = IPCValue.array([.string("a"), .int(1), .bool(false)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(IPCValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded.arrayValue?.count == 3)
    }

    @Test("IPCValue object round-trips through JSON")
    func objectRoundTrip() throws {
        let value = IPCValue.object(["key": .string("val"), "num": .int(5)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(IPCValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded.objectValue?["key"]?.stringValue == "val")
    }

    @Test("IPCValue nested structure round-trips")
    func nestedRoundTrip() throws {
        let value = IPCValue.object([
            "sessions": .array([
                .object(["id": .string("abc"), "active": .bool(true)]),
                .object(["id": .string("def"), "active": .bool(false)]),
            ]),
            "count": .int(2),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(IPCValue.self, from: data)
        #expect(decoded == value)
    }

    // MARK: - IPCValue accessor returns nil for wrong type

    @Test("IPCValue accessors return nil for mismatched types")
    func accessorMismatch() {
        let str = IPCValue.string("hello")
        #expect(str.intValue == nil)
        #expect(str.boolValue == nil)
        #expect(str.arrayValue == nil)
        #expect(str.objectValue == nil)

        let num = IPCValue.int(42)
        #expect(num.stringValue == nil)
        #expect(num.boolValue == nil)
    }

    // MARK: - IPCRequest encoding

    @Test("IPCRequest encodes action and params")
    func requestEncoding() throws {
        let request = IPCRequest(
            action: "addFolder",
            params: ["path": .string("/tmp")]
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(IPCRequest.self, from: data)
        #expect(decoded.action == "addFolder")
        #expect(decoded.params?["path"]?.stringValue == "/tmp")
    }

    @Test("IPCRequest encodes nil params")
    func requestNilParams() throws {
        let request = IPCRequest(action: "listSessions", params: nil)
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(IPCRequest.self, from: data)
        #expect(decoded.action == "listSessions")
        #expect(decoded.params == nil)
    }

    // MARK: - IPCResponse encoding

    @Test("IPCResponse success round-trips")
    func responseSuccess() throws {
        let response = IPCResponse.success(.string("ok"))
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)
        #expect(decoded.ok == true)
        #expect(decoded.data?.stringValue == "ok")
        #expect(decoded.error == nil)
    }

    @Test("IPCResponse failure round-trips")
    func responseFailure() throws {
        let response = IPCResponse.failure("something broke")
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)
        #expect(decoded.ok == false)
        #expect(decoded.data == nil)
        #expect(decoded.error == "something broke")
    }

    // MARK: - Socket path

    @Test("socket path ends with mcp.sock")
    func socketPath() {
        let path = IPCProtocol.socketPath
        #expect(path.hasSuffix("TermHub/mcp.sock"))
    }
}
