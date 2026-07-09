import Foundation

struct CommandResult: Sendable {
    let output: String
    let errorOutput: String
    let exitCode: Int32
}

enum CommandLogger {
    static func log(executablePath: String, arguments: [String]) {
        print("[TermHub] Running command: \(formatCommandLine(executablePath: executablePath, arguments: arguments))")
    }

    private static func formatCommandLine(executablePath: String, arguments: [String]) -> String {
        ([executablePath] + arguments).map(shellQuote).joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }
        if value.rangeOfCharacter(from: CharacterSet(charactersIn: " \t\n\r'\"\\$&;|<>*?()[]{}!")) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

protocol CommandRunner: Sendable {
    func run(executablePath: String, arguments: [String], environment: [String: String]?) -> CommandResult
}

struct ProcessCommandRunner: CommandRunner {
    func run(executablePath: String, arguments: [String], environment: [String: String]?) -> CommandResult {
        CommandLogger.log(executablePath: executablePath, arguments: arguments)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return CommandResult(output: "", errorOutput: error.localizedDescription, exitCode: -1)
        }

        // Read pipe data BEFORE waitUntilExit to avoid deadlock.
        // If the process fills the pipe buffer (~64KB), it blocks waiting
        // for the reader to drain — while we block waiting for exit.
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        return CommandResult(output: output, errorOutput: errorOutput, exitCode: process.terminationStatus)
    }
}
