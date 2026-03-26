import Foundation

// MARK: - MCP Server (JSON-RPC over stdio)

let serverInfo: JSONValue = .object([
    "name": .string("termhub"),
    "version": .string("1.0.0"),
])

let serverCapabilities: JSONValue = .object([
    "tools": .object([:]),
])

func handleRequest(_ request: JSONRPCRequest) -> JSONRPCResponse? {
    switch request.method {
    case "initialize":
        return .result(.object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": serverCapabilities,
            "serverInfo": serverInfo,
        ]), id: request.id)

    case "notifications/initialized":
        // Client notification — no response needed
        return nil

    case "tools/list":
        return .result(.object([
            "tools": .array(MCPTools.allTools),
        ]), id: request.id)

    case "tools/call":
        guard let params = request.params,
              let name = params["name"]?.stringValue else {
            return .error(code: -32602, message: "Missing tool name", id: request.id)
        }

        let arguments: [String: JSONValue]
        if let argsValue = params["arguments"],
           let argsObj = argsValue.objectValue {
            arguments = argsObj
        } else {
            arguments = [:]
        }

        let result = MCPTools.call(name: name, arguments: arguments)
        return .result(MCPTools.textResult(result), id: request.id)

    case "ping":
        return .result(.object([:]), id: request.id)

    default:
        if request.id != nil {
            return .error(code: -32601, message: "Method not found: \(request.method)", id: request.id)
        }
        // Unknown notification — ignore
        return nil
    }
}

func extractMessage(from buffer: Data, decoder: JSONDecoder) -> (JSONRPCRequest, Int)? {
    guard let str = String(data: buffer, encoding: .utf8) else { return nil }

    // Try Content-Length framing first (standard MCP transport)
    if let headerEnd = str.range(of: "\r\n\r\n") {
        let headerSection = str[str.startIndex..<headerEnd.lowerBound]
        if let lengthLine = headerSection.split(separator: "\r\n").first(where: {
            $0.lowercased().hasPrefix("content-length:")
        }) {
            let lengthStr = lengthLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
            if let contentLength = Int(lengthStr), contentLength > 0 {
                let headerSize = str.utf8.distance(from: str.utf8.startIndex, to: headerEnd.upperBound.samePosition(in: str.utf8)!)
                let totalSize = headerSize + contentLength

                guard buffer.count >= totalSize else { return nil }

                let bodyData = buffer[buffer.startIndex.advanced(by: headerSize)..<buffer.startIndex.advanced(by: totalSize)]
                if let request = try? decoder.decode(JSONRPCRequest.self, from: Data(bodyData)) {
                    return (request, totalSize)
                }
            }
        }
    }

    // Fall back to newline-delimited JSON (used by Claude Code)
    guard let newlineRange = str.range(of: "\n") else { return nil }
    let line = str[str.startIndex..<newlineRange.lowerBound]
    let lineBytes = str.utf8.distance(from: str.utf8.startIndex, to: newlineRange.upperBound.samePosition(in: str.utf8)!)
    guard let lineData = line.data(using: .utf8),
          let request = try? decoder.decode(JSONRPCRequest.self, from: lineData) else {
        // Skip malformed line — return a sentinel consumed count via a wrapper
        return nil
    }
    return (request, lineBytes)
}
