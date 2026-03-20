import Foundation

enum ShellEnvironment {
    static var defaultShell: String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }
        return "/bin/zsh"
    }

    static var userPath: String {
        if let path = ProcessInfo.processInfo.environment["PATH"], !path.isEmpty {
            return path
        }
        return "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }

    static var tmuxPath: String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        // Try finding via PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["tmux"]
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

    static var shellEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = userPath
        env["TERM"] = "xterm-256color"
        return env
    }
}
