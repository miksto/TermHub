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
                if var responseData = try? encoder.encode(response) {
                    responseData.append(0x0A)  // newline delimiter
                    stdout.write(responseData)
                }
            }
        }
    }
}

// Start the server
runServer()
