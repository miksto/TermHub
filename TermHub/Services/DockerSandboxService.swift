import Foundation

// All lifecycle methods (listSandboxes, createSandbox, etc.) are synchronous
// and perform blocking I/O. They must NEVER be called from the main thread.
// Use Task.detached {} when calling from @MainActor contexts.

enum SandboxAgent: String, CaseIterable, Sendable {
    case claude
    case copilot
    case codex
    case gemini
    case cagent
    case kiro
    case opencode
    case shell

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .copilot: "GitHub Copilot"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .cagent: "Docker Agent"
        case .kiro: "Kiro"
        case .opencode: "OpenCode"
        case .shell: "Shell"
        }
    }
}

enum DockerSandboxError: Error, LocalizedError, Equatable {
    case dockerNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .dockerNotFound:
            return "docker binary not found"
        case .commandFailed(let message):
            return "docker sandbox command failed: \(message)"
        }
    }
}

enum DockerSandboxService {
    static let dockerPath: String? = resolveDockerPath()
    nonisolated(unsafe) static var commandRunner: CommandRunner = ProcessCommandRunner()
    /// Override for testing. When set, bypasses the resolved dockerPath.
    nonisolated(unsafe) static var dockerPathOverride: String?

    private static var resolvedDockerPath: String? {
        dockerPathOverride ?? dockerPath
    }

    /// Docker sandbox names must start with an alphanumeric character and contain only `[a-zA-Z0-9_.-]`.
    static func isValidSandboxName(_ name: String) -> Bool {
        let pattern = /^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/
        return name.wholeMatch(of: pattern) != nil
    }

    /// Environment variable keys must start with a letter or underscore, followed by `[a-zA-Z0-9_]`.
    static func isValidEnvVarKey(_ key: String) -> Bool {
        let pattern = /^[a-zA-Z_][a-zA-Z0-9_]*$/
        return key.wholeMatch(of: pattern) != nil
    }

    /// Resolves environment variable names to their current values from the host environment.
    /// Keys that are not set on the host or have invalid names are skipped.
    static func resolveEnvironmentVariables(keys: [String]) -> [String: String] {
        let hostEnv = ProcessInfo.processInfo.environment
        var result: [String: String] = [:]
        for key in keys {
            guard isValidEnvVarKey(key), let value = hostEnv[key] else { continue }
            result[key] = value
        }
        return result
    }

    /// Returns the shell command string for tmux to execute inside a sandbox.
    static func execCommand(sandboxName: String, cwd: String, environmentVariables: [String: String] = [:]) -> String {
        guard let docker = resolvedDockerPath else {
            return "echo 'docker not found'; exit 1"
        }
        guard isValidSandboxName(sandboxName) else {
            return "echo 'Invalid sandbox name'; exit 1"
        }
        let envFlags = environmentVariables
            .sorted(by: { $0.key < $1.key })
            .compactMap { key, value -> String? in
                guard isValidEnvVarKey(key) else { return nil }
                let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
                return "-e '\(key)=\(escapedValue)'"
            }
            .joined(separator: " ")
        let escapedCwd = cwd.replacingOccurrences(of: "'", with: "'\\''")
        let envPart = envFlags.isEmpty ? "" : " \(envFlags)"
        return "\(docker) sandbox exec\(envPart) -it \(sandboxName) bash -c 'cd \(escapedCwd) && exec bash'"
    }

    // MARK: - Lifecycle Methods

    @discardableResult
    private static func run(_ arguments: [String]) throws -> String {
        guard let docker = resolvedDockerPath else {
            throw DockerSandboxError.dockerNotFound
        }
        let result = commandRunner.run(
            executablePath: docker,
            arguments: ["sandbox"] + arguments,
            environment: ShellEnvironment.shellEnvironment
        )

        if result.exitCode != 0 {
            let message = result.errorOutput.isEmpty ? result.output : result.errorOutput
            throw DockerSandboxError.commandFailed(message)
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lists all Docker sandboxes. Returns empty array on failure.
    static func listSandboxes() -> [SandboxInfo] {
        do {
            let output = try run(["ls", "--json"])
            guard let data = output.data(using: .utf8) else { return [] }
            let response = try JSONDecoder().decode(SandboxListResponse.self, from: data)
            return response.vms
        } catch {
            return []
        }
    }

    /// Creates a new sandbox for the given agent with workspace paths.
    static func createSandbox(name: String, agent: String = "claude", workspaces: [String]) throws {
        let args = ["create", "--name", name, agent] + workspaces
        try run(args)
    }

    /// Stops a running sandbox without removing it.
    static func stopSandbox(name: String) throws {
        try run(["stop", name])
    }

    /// Removes a sandbox and all its associated resources.
    static func removeSandbox(name: String) throws {
        try run(["rm", name])
    }

    private static func resolveDockerPath() -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker",
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["docker"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty {
                    return path
                }
            }
        } catch {}
        return nil
    }
}
