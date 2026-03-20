import Foundation
import SwiftTerm

@MainActor
final class TerminalSessionManager {
    private var terminals: [UUID: LocalProcessTerminalView] = [:]
    private var startedSessions: Set<UUID> = []

    func getOrCreateTerminal(for session: TerminalSession, tmuxAvailable: Bool) -> LocalProcessTerminalView {
        if let existing = terminals[session.id] {
            return existing
        }

        let terminal = LocalProcessTerminalView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        terminals[session.id] = terminal
        return terminal
    }

    /// Start the shell/tmux process. Must be called after the view is in the window hierarchy.
    func startProcessIfNeeded(for session: TerminalSession, tmuxAvailable: Bool) {
        guard !startedSessions.contains(session.id) else { return }
        guard let terminal = terminals[session.id] else { return }
        startedSessions.insert(session.id)

        let shell = ShellEnvironment.defaultShell
        let cwd = session.worktreePath ?? session.workingDirectory

        if tmuxAvailable {
            if !TmuxService.sessionExists(name: session.tmuxSessionName) {
                try? TmuxService.createSession(name: session.tmuxSessionName, cwd: cwd)
            }
            let cmd = TmuxService.attachCommand(name: session.tmuxSessionName)
            let executable = cmd[0]
            let args = Array(cmd.dropFirst())
            terminal.startProcess(
                executable: executable,
                args: args,
                environment: ShellEnvironment.shellEnvironment.map { "\($0.key)=\($0.value)" },
                execName: (executable as NSString).lastPathComponent
            )
        } else {
            terminal.startProcess(
                executable: shell,
                args: [],
                environment: ShellEnvironment.shellEnvironment.map { "\($0.key)=\($0.value)" },
                execName: (shell as NSString).lastPathComponent,
                currentDirectory: cwd
            )
        }
    }

    func sessionID(for terminal: LocalProcessTerminalView) -> UUID? {
        terminals.first { $0.value === terminal }?.key
    }

    func destroyTerminal(for sessionID: UUID) {
        terminals.removeValue(forKey: sessionID)
        startedSessions.remove(sessionID)
    }
}
