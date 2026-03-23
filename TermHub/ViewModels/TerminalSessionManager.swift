import Foundation
import SwiftTerm

@MainActor
final class TerminalSessionManager {
    private var terminals: [UUID: LocalProcessTerminalView] = [:]
    private var delegates: [UUID: TerminalProcessDelegate] = [:]
    private var startedSessions: Set<UUID> = []
    private var destroyedSessionIDs: Set<UUID> = []
    private var startRetryCount: [UUID: Int] = [:]
    private static let maxStartRetries = 50
    var pendingCommands: [UUID: String] = [:]
    var onBell: ((UUID) -> Void)?
    var onTitleChange: ((UUID, String) -> Void)?

    func getOrCreateTerminal(for session: TerminalSession, tmuxAvailable: Bool) -> LocalProcessTerminalView? {
        if let existing = terminals[session.id] {
            return existing
        }

        if destroyedSessionIDs.contains(session.id) {
            return nil
        }

        let terminal = TermHubTerminalView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        let sessionID = session.id
        terminal.onBell = { [weak self] in
            Task { @MainActor in
                self?.onBell?(sessionID)
            }
        }

        let delegate = TerminalProcessDelegate(manager: self, sessionID: sessionID)
        delegates[sessionID] = delegate
        terminal.processDelegate = delegate

        terminals[session.id] = terminal
        return terminal
    }

    /// Start the shell/tmux process. Must be called after the view is in the window hierarchy.
    func startProcessIfNeeded(for session: TerminalSession, tmuxAvailable: Bool, sandboxName: String? = nil) {
        guard !startedSessions.contains(session.id) else { return }
        guard let terminal = terminals[session.id] else { return }
        guard terminal.window != nil else {
            // Terminal not yet in window hierarchy. Retry on next run loop cycle.
            let retries = startRetryCount[session.id, default: 0]
            guard retries < Self.maxStartRetries else {
                print("[TermHub] Gave up waiting for terminal window after \(retries) retries (session \(session.id))")
                startRetryCount.removeValue(forKey: session.id)
                return
            }
            startRetryCount[session.id] = retries + 1
            let session = session
            let tmuxAvailable = tmuxAvailable
            let sandboxName = sandboxName
            DispatchQueue.main.async { [weak self] in
                self?.startProcessIfNeeded(for: session, tmuxAvailable: tmuxAvailable, sandboxName: sandboxName)
            }
            return
        }
        startRetryCount.removeValue(forKey: session.id)
        startedSessions.insert(session.id)

        let shell = ShellEnvironment.defaultShell
        let cwd = session.worktreePath ?? session.workingDirectory

        if tmuxAvailable {
            let tmuxSessionName = session.tmuxSessionName
            let pendingCommand = pendingCommands.removeValue(forKey: session.id)
            let env = ShellEnvironment.shellEnvironment
            let sandboxCmd: String? = if session.isSandboxSession, let sandboxName {
                DockerSandboxService.execCommand(sandboxName: sandboxName, cwd: cwd)
            } else {
                nil
            }

            // Run blocking tmux process calls off the main thread to avoid
            // re-entrant run-loop spinning during SwiftUI layout updates.
            Task.detached {
                if !TmuxService.sessionExists(name: tmuxSessionName) {
                    do {
                        try TmuxService.createSession(name: tmuxSessionName, cwd: cwd, shellCommand: sandboxCmd)
                    } catch {
                        print("[TermHub] Failed to create tmux session '\(tmuxSessionName)': \(error)")
                    }
                }

                await MainActor.run {
                    // Suppress rendering during the initial tmux buffer replay
                    // so the terminal appears at the bottom instantly.
                    (terminal as? TermHubTerminalView)?.suppressRendering = true

                    let cmd = TmuxService.attachCommand(name: tmuxSessionName)
                    let executable = cmd[0]
                    let args = Array(cmd.dropFirst())
                    terminal.startProcess(
                        executable: executable,
                        args: args,
                        environment: env.map { "\($0.key)=\($0.value)" },
                        execName: (executable as NSString).lastPathComponent
                    )
                }

                if let command = pendingCommand {
                    try? await Task.sleep(for: .milliseconds(500))
                    try? TmuxService.sendKeys(sessionName: tmuxSessionName, text: command)
                }
            }
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

    func markProcessTerminated(for sessionID: UUID) {
        print("[TermHub] Process terminated for session \(sessionID)")
        startedSessions.remove(sessionID)
    }

    func terminal(for sessionID: UUID) -> LocalProcessTerminalView? {
        terminals[sessionID]
    }

    func sessionID(for terminal: LocalProcessTerminalView) -> UUID? {
        terminals.first { $0.value === terminal }?.key
    }

    func destroyTerminal(for sessionID: UUID) {
        destroyedSessionIDs.insert(sessionID)
        if let terminal = terminals.removeValue(forKey: sessionID) {
            (terminal as? TermHubTerminalView)?.removeEventMonitors()
            terminal.removeFromSuperview()
        }
        delegates.removeValue(forKey: sessionID)
        startedSessions.remove(sessionID)
        startRetryCount.removeValue(forKey: sessionID)
    }
}

private final class TerminalProcessDelegate: LocalProcessTerminalViewDelegate {
    private weak var manager: TerminalSessionManager?
    private let sessionID: UUID

    init(manager: TerminalSessionManager, sessionID: UUID) {
        self.manager = manager
        self.sessionID = sessionID
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let manager = manager
        let sessionID = sessionID
        Task { @MainActor in
            manager?.onTitleChange?(sessionID, title)
        }
    }
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        let manager = manager
        let sessionID = sessionID
        print("[TermHub] Process exited for session \(sessionID), exitCode: \(String(describing: exitCode))")
        Task { @MainActor in
            manager?.markProcessTerminated(for: sessionID)
        }
    }
}
