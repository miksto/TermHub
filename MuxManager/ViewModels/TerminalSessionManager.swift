import Foundation
import SwiftTerm

@MainActor
final class TerminalSessionManager {
    private var terminals: [UUID: LocalProcessTerminalView] = [:]

    func getOrCreateTerminal(for session: TerminalSession, tmuxAvailable: Bool) -> LocalProcessTerminalView {
        if let existing = terminals[session.id] {
            return existing
        }

        let terminal = LocalProcessTerminalView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        terminals[session.id] = terminal

        let shell = ShellEnvironment.defaultShell
        let cwd = session.worktreePath ?? session.workingDirectory

        if tmuxAvailable {
            // Ensure tmux session exists
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

        return terminal
    }

    func destroyTerminal(for sessionID: UUID) {
        terminals.removeValue(forKey: sessionID)
    }
}
