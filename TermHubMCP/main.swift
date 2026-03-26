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

// MARK: - stdio I/O loop

func runServer() {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let stdin = FileHandle.standardInput
    let stdout = FileHandle.standardOutput

    var buffer = Data()

    while true {
        let chunk = stdin.availableData
        if chunk.isEmpty {
            // stdin closed — exit
            break
        }
        buffer.append(chunk)

        // Process all complete messages in the buffer
        while let (request, consumed) = extractMessage(from: buffer, decoder: decoder) {
            buffer = buffer.dropFirst(consumed) as Data

            if let response = handleRequest(request) {
                if let responseData = try? encoder.encode(response) {
                    var output = Data()
                    let header = "Content-Length: \(responseData.count)\r\n\r\n"
                    output.append(header.data(using: .utf8)!)
                    output.append(responseData)
                    stdout.write(output)
                }
            }
        }
    }
}

func extractMessage(from buffer: Data, decoder: JSONDecoder) -> (JSONRPCRequest, Int)? {
    guard let str = String(data: buffer, encoding: .utf8) else { return nil }

    // Look for Content-Length header
    guard let headerEnd = str.range(of: "\r\n\r\n") else { return nil }

    let headerSection = str[str.startIndex..<headerEnd.lowerBound]
    guard let lengthLine = headerSection.split(separator: "\r\n").first(where: {
        $0.lowercased().hasPrefix("content-length:")
    }) else { return nil }

    let lengthStr = lengthLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
    guard let contentLength = Int(lengthStr), contentLength > 0 else { return nil }

    let headerSize = str.distance(from: str.startIndex, to: headerEnd.upperBound)
    let totalSize = headerSize + contentLength

    guard buffer.count >= totalSize else { return nil }

    let bodyData = buffer[buffer.startIndex.advanced(by: headerSize)..<buffer.startIndex.advanced(by: totalSize)]
    guard let request = try? decoder.decode(JSONRPCRequest.self, from: Data(bodyData)) else {
        // Skip malformed messages
        return nil
    }

    return (request, totalSize)
}

// Start the server
runServer()
