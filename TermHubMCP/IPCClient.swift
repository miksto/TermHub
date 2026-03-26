import Foundation

enum IPCClientError: Error, LocalizedError {
    case connectionFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "IPC connection failed: \(msg)"
        case .sendFailed(let msg): return "IPC send failed: \(msg)"
        case .receiveFailed(let msg): return "IPC receive failed: \(msg)"
        case .invalidResponse: return "Invalid IPC response"
        }
    }
}

enum IPCClient {
    static func send(action: String, params: [String: IPCValue]? = nil) throws -> IPCResponse {
        let socketPath = IPCProtocol.socketPath

        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw IPCClientError.connectionFailed("TermHub is not running (socket not found at \(socketPath))")
        }

        let socket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw IPCClientError.connectionFailed("Failed to create socket")
        }
        defer { close(socket) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        precondition(pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path), "Socket path too long")
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
            for (i, byte) in pathBytes.enumerated() {
                rawBuf[i] = UInt8(bitPattern: byte)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            throw IPCClientError.connectionFailed("Failed to connect to TermHub IPC socket (errno: \(errno))")
        }

        let request = IPCRequest(action: action, params: params)
        guard let jsonData = try? JSONEncoder().encode(request) else {
            throw IPCClientError.sendFailed("Failed to encode request")
        }

        // Send 4-byte big-endian length prefix + JSON payload
        var length = UInt32(jsonData.count).bigEndian
        let lengthData = Data(bytes: &length, count: 4)

        guard sendAll(socket, data: lengthData) && sendAll(socket, data: jsonData) else {
            throw IPCClientError.sendFailed("Failed to write to socket")
        }

        // Read 4-byte response length
        guard let responseLengthData = recvExact(socket, count: 4) else {
            throw IPCClientError.receiveFailed("Failed to read response length")
        }

        let responseLength = responseLengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard responseLength > 0, responseLength < 10_000_000 else {
            throw IPCClientError.invalidResponse
        }

        guard let responseData = recvExact(socket, count: Int(responseLength)) else {
            throw IPCClientError.receiveFailed("Failed to read response body")
        }

        guard let response = try? JSONDecoder().decode(IPCResponse.self, from: responseData) else {
            throw IPCClientError.invalidResponse
        }

        return response
    }

    private static func sendAll(_ fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return false }
            var sent = 0
            while sent < data.count {
                let result = Foundation.send(fd, ptr.advanced(by: sent), data.count - sent, 0)
                if result <= 0 { return false }
                sent += result
            }
            return true
        }
    }

    private static func recvExact(_ fd: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        var received = 0
        let success = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let ptr = buffer.baseAddress else { return false }
            while received < count {
                let result = recv(fd, ptr.advanced(by: received), count - received, 0)
                if result <= 0 { return false }
                received += result
            }
            return true
        }
        return success ? data : nil
    }
}
