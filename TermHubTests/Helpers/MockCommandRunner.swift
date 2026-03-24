import Foundation
@testable import TermHub

final class MockCommandRunner: CommandRunner, @unchecked Sendable {
    struct Call: Sendable {
        let executablePath: String
        let arguments: [String]
    }

    private(set) var calls: [Call] = []
    private var results: [CommandResult] = []
    private var callIndex = 0

    /// Queue a result to be returned on the next `run` call.
    func enqueue(output: String = "", errorOutput: String = "", exitCode: Int32 = 0) {
        results.append(CommandResult(output: output, errorOutput: errorOutput, exitCode: exitCode))
    }

    /// Queue a successful result with the given output.
    func enqueueSuccess(_ output: String = "") {
        enqueue(output: output, exitCode: 0)
    }

    /// Queue a failure result.
    func enqueueFailure(_ errorOutput: String = "command failed", exitCode: Int32 = 1) {
        enqueue(errorOutput: errorOutput, exitCode: exitCode)
    }

    func run(executablePath: String, arguments: [String], environment: [String: String]?) -> CommandResult {
        calls.append(Call(executablePath: executablePath, arguments: arguments))
        guard callIndex < results.count else {
            return CommandResult(output: "", errorOutput: "no mock result configured", exitCode: 1)
        }
        let result = results[callIndex]
        callIndex += 1
        return result
    }

    func reset() {
        calls = []
        results = []
        callIndex = 0
    }

    var lastCall: Call? { calls.last }
    var callCount: Int { calls.count }
}
