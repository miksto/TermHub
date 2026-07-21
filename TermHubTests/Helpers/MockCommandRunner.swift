import Foundation
@testable import TermHub

final class MockCommandRunner: CommandRunner, @unchecked Sendable {
    struct Call: Sendable {
        let executablePath: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private var callsStorage: [Call] = []
    private var results: [CommandResult] = []
    private var callIndex = 0
    private var handlerStorage: (@Sendable (_ executablePath: String, _ arguments: [String], _ environment: [String: String]?) -> CommandResult)?

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return callsStorage
    }

    var handler: (@Sendable (_ executablePath: String, _ arguments: [String], _ environment: [String: String]?) -> CommandResult)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return handlerStorage
        }
        set {
            lock.lock()
            handlerStorage = newValue
            lock.unlock()
        }
    }

    /// Queue a result to be returned on the next `run` call.
    func enqueue(output: String = "", errorOutput: String = "", exitCode: Int32 = 0) {
        lock.lock()
        results.append(CommandResult(output: output, errorOutput: errorOutput, exitCode: exitCode))
        lock.unlock()
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
        lock.lock()
        callsStorage.append(Call(executablePath: executablePath, arguments: arguments))
        let handler = handlerStorage
        let result: CommandResult?
        if handler == nil, callIndex < results.count {
            result = results[callIndex]
            callIndex += 1
        } else {
            result = nil
        }
        lock.unlock()

        if let handler {
            return handler(executablePath, arguments, environment)
        }
        return result ?? CommandResult(output: "", errorOutput: "no mock result configured", exitCode: 1)
    }

    func reset() {
        lock.lock()
        callsStorage = []
        results = []
        callIndex = 0
        handlerStorage = nil
        lock.unlock()
    }

    var lastCall: Call? { calls.last }
    var callCount: Int { calls.count }
}
