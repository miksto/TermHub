import Foundation

enum TmuxServiceError: Error, LocalizedError {
    case tmuxNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .tmuxNotFound:
            return "tmux binary not found"
        case .commandFailed(let message):
            return "tmux command failed: \(message)"
        }
    }
}

enum TmuxService {
    private static let socketName = "termhub"
    nonisolated(unsafe) private static var didConfigureServer = false

    @discardableResult
    private static func run(_ arguments: [String]) throws -> String {
        guard let tmux = ShellEnvironment.tmuxPath else {
            throw TmuxServiceError.tmuxNotFound
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmux)
        process.arguments = ["-L", socketName] + arguments
        process.environment = ShellEnvironment.shellEnvironment

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if process.terminationStatus != 0 {
            throw TmuxServiceError.commandFailed(errorOutput.isEmpty ? output : errorOutput)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ensureServerConfigured() throws {
        guard !didConfigureServer else { return }
        try run(["set-option", "-g", "mouse", "on"])
        // Forward pane title changes from the inner shell to the outer terminal (SwiftTerm),
        // so that setTerminalTitle fires and the session title updates dynamically.
        try run(["set-option", "-g", "set-titles", "on"])
        try run(["set-option", "-g", "set-titles-string", "#{pane_title}"])
        didConfigureServer = true
    }

    static func createSession(name: String, cwd: String) throws {
        try run(["new-session", "-d", "-s", name, "-c", cwd])
        try ensureServerConfigured()
    }

    static func attachCommand(name: String) -> [String] {
        guard let tmux = ShellEnvironment.tmuxPath else {
            return [ShellEnvironment.defaultShell]
        }
        return [tmux, "-L", socketName, "attach-session", "-t", name]
    }

    static func killSession(name: String) throws {
        try run(["kill-session", "-t", name])
    }

    static func renameSession(oldName: String, newName: String) throws {
        try run(["rename-session", "-t", oldName, newName])
    }

    static func sessionExists(name: String) -> Bool {
        do {
            try run(["has-session", "-t", name])
            return true
        } catch {
            return false
        }
    }

    static func isAvailable() -> Bool {
        return ShellEnvironment.tmuxPath != nil
    }
}
