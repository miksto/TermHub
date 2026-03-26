import Foundation

// MARK: - JSON-RPC Types

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: [String: JSONValue]?
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let result: JSONValue?
    let error: JSONRPCError?

    static func result(_ value: JSONValue, id: JSONRPCId?) -> JSONRPCResponse {
        JSONRPCResponse(jsonrpc: "2.0", id: id, result: value, error: nil)
    }

    static func error(code: Int, message: String, id: JSONRPCId?) -> JSONRPCResponse {
        JSONRPCResponse(jsonrpc: "2.0", id: id, result: nil, error: JSONRPCError(code: code, message: message))
    }
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
}

struct JSONRPCNotification: Codable {
    let jsonrpc: String
    let method: String
    let params: [String: JSONValue]?
}

// MARK: - JSON-RPC ID (can be string or int)

enum JSONRPCId: Codable, Equatable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "ID must be string or int")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        }
    }
}

// MARK: - Generic JSON Value

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let obj) = self { return obj }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let arr) = self { return arr }
        return nil
    }
}
