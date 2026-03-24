import Foundation

// All methods in TmuxService are synchronous and perform blocking I/O
// (Process + waitUntilExit). They must NEVER be called from the main thread.
// Use Task.detached {} when calling from @MainActor contexts.

enum TmuxServiceError: Error, LocalizedError, Equatable {
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
    nonisolated(unsafe) static var commandRunner: CommandRunner = ProcessCommandRunner()
    /// Override for testing. When set, bypasses ShellEnvironment.tmuxPath.
    nonisolated(unsafe) static var tmuxPathOverride: String?

    private static var resolvedTmuxPath: String? {
        tmuxPathOverride ?? ShellEnvironment.tmuxPath
    }

    @discardableResult
    private static func run(_ arguments: [String]) throws -> String {
        guard let tmux = resolvedTmuxPath else {
            throw TmuxServiceError.tmuxNotFound
        }
        let result = commandRunner.run(
            executablePath: tmux,
            arguments: ["-L", socketName] + arguments,
            environment: ShellEnvironment.shellEnvironment
        )

        if result.exitCode != 0 {
            let message = result.errorOutput.isEmpty ? result.output : result.errorOutput
            throw TmuxServiceError.commandFailed(message)
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
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

    static func createSession(name: String, cwd: String, shellCommand: String? = nil) throws {
        if let shellCommand {
            try run(["new-session", "-d", "-s", name, "-c", cwd, shellCommand])
        } else {
            try run(["new-session", "-d", "-s", name, "-c", cwd])
        }
        try ensureServerConfigured()
    }

    static func attachCommand(name: String) -> [String] {
        guard let tmux = resolvedTmuxPath else {
            return [ShellEnvironment.defaultShell]
        }
        return [tmux, "-L", socketName, "attach-session", "-t", name]
    }

    static func killSession(name: String) throws {
        try run(["kill-session", "-t", name])
    }

    static func sessionExists(name: String) -> Bool {
        do {
            try run(["has-session", "-t", name])
            return true
        } catch {
            return false
        }
    }

    static func sendKeys(sessionName: String, text: String) throws {
        try run(["send-keys", "-t", sessionName, text, "Enter"])
    }

    /// Returns the names of all sessions on the termhub socket.
    static func listSessions() -> [String] {
        guard let output = try? run(["list-sessions", "-F", "#{session_name}"]) else {
            return []
        }
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    static func isAvailable() -> Bool {
        return resolvedTmuxPath != nil
    }

    /// Reset internal state for testing.
    static func resetForTesting() {
        didConfigureServer = false
    }
}
