import Foundation

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

// Start the server
runServer()
