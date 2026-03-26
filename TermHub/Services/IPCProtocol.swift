import Foundation

enum IPCProtocol {
    static var socketPath: String {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return "/tmp/termhub-mcp.sock"
        }
        return appSupport
            .appendingPathComponent("TermHub", isDirectory: true)
            .appendingPathComponent("mcp.sock")
            .path
    }
}

struct IPCRequest: Codable, Sendable {
    let action: String
    let params: [String: IPCValue]?
}

struct IPCResponse: Codable, Sendable {
    let ok: Bool
    let data: IPCValue?
    let error: String?

    static func success(_ data: IPCValue? = nil) -> IPCResponse {
        IPCResponse(ok: true, data: data, error: nil)
    }

    static func failure(_ error: String) -> IPCResponse {
        IPCResponse(ok: false, data: nil, error: error)
    }
}

/// A lightweight JSON value type for IPC payloads.
enum IPCValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([IPCValue])
    case object([String: IPCValue])

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
        } else if let arr = try? container.decode([IPCValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: IPCValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported IPCValue type")
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

    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var arrayValue: [IPCValue]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    var objectValue: [String: IPCValue]? {
        if case .object(let obj) = self { return obj }
        return nil
    }
}
