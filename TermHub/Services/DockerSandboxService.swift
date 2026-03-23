import Foundation

enum DockerSandboxService {
    static var dockerPath: String? {
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

    /// Returns the shell command string for tmux to execute inside a sandbox.
    static func execCommand(sandboxName: String, cwd: String) -> String {
        guard let docker = dockerPath else {
            return "echo 'docker not found'; exit 1"
        }
        let escapedCwd = cwd.replacingOccurrences(of: "'", with: "'\\''")
        return "\(docker) sandbox exec -it \(sandboxName) bash -c 'cd \(escapedCwd) && exec bash'"
    }
}
