import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var folders: [ManagedFolder] = []
    var sessions: [TerminalSession] = []
    var selectedSessionID: UUID?
    var tmuxAvailable: Bool = false
    var pendingWorktreeFolder: ManagedFolder?
    var pendingNewBranchFolder: ManagedFolder?
    var errorMessage: String?
    var showingAddFolder = false
    var pendingCloseSessionID: UUID?

    let terminalManager = TerminalSessionManager()

    init() {
        tmuxAvailable = TmuxService.isAvailable()
        loadState()
        restoreTmuxSessions()
    }

    var selectedSession: TerminalSession? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    /// All sessions ordered by folder for keyboard navigation.
    var allSessionIDsOrdered: [UUID] {
        folders.flatMap { folder in
            folder.sessionIDs.filter { id in sessions.contains { $0.id == id } }
        }
    }

    func addFolder(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            errorMessage = "Folder path does not exist: \(path)"
            return
        }

        let folder = ManagedFolder(path: path)
        folders.append(folder)

        // Auto-create a default session for the folder
        let session = TerminalSession(
            folderID: folder.id,
            title: folder.name,
            workingDirectory: path
        )
        sessions.append(session)
        var updated = folders[folders.count - 1]
        updated.sessionIDs.append(session.id)
        folders[folders.count - 1] = updated

        // Create tmux session
        if tmuxAvailable, !TmuxService.sessionExists(name: session.tmuxSessionName) {
            do {
                try TmuxService.createSession(name: session.tmuxSessionName, cwd: path)
            } catch {
                errorMessage = "Failed to create tmux session: \(error.localizedDescription)"
            }
        }

        saveState()

        if selectedSessionID == nil {
            selectedSessionID = session.id
        }
    }

    func removeFolder(id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let folder = folders[index]

        // Remove all sessions belonging to this folder (with cleanup)
        for sessionID in folder.sessionIDs {
            removeSession(id: sessionID, parentFolderPath: folder.path, save: false)
        }

        folders.remove(at: index)
        saveState()
    }

    func addSession(
        folderID: UUID,
        title: String,
        cwd: String,
        worktreePath: String? = nil,
        branchName: String? = nil
    ) {
        let session = TerminalSession(
            folderID: folderID,
            title: title,
            workingDirectory: cwd,
            worktreePath: worktreePath,
            branchName: branchName
        )

        // Create the tmux session immediately so the terminal is ready
        if tmuxAvailable, !TmuxService.sessionExists(name: session.tmuxSessionName) {
            do {
                try TmuxService.createSession(name: session.tmuxSessionName, cwd: cwd)
            } catch {
                errorMessage = "Failed to create tmux session: \(error.localizedDescription)"
            }
        }
        sessions.append(session)

        if let folderIndex = folders.firstIndex(where: { $0.id == folderID }) {
            folders[folderIndex].sessionIDs.append(session.id)
        }

        selectedSessionID = session.id
        saveState()
    }

    func removeSession(id: UUID, parentFolderPath: String? = nil, save: Bool = true) {
        // Find the session before removing
        guard let session = sessions.first(where: { $0.id == id }) else { return }

        // Perform tmux + worktree cleanup
        try? TmuxService.killSession(name: session.tmuxSessionName)
        if let worktreePath = session.worktreePath {
            let folderPath = parentFolderPath ?? folders.first(where: { $0.id == session.folderID })?.path
            if let repoPath = folderPath {
                try? GitService.removeWorktree(repoPath: repoPath, worktreePath: worktreePath)
            }
        }

        // Auto-select next sibling before removing
        if selectedSessionID == id {
            selectedSessionID = nextSessionID(after: id, inFolderOf: session)
        }

        terminalManager.destroyTerminal(for: id)
        sessions.removeAll { $0.id == id }

        // Remove from folder's sessionIDs
        for i in folders.indices {
            folders[i].sessionIDs.removeAll { $0 == id }
        }

        if save { saveState() }
    }

    func renameSession(id: UUID, newTitle: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = newTitle
        saveState()
    }

    func selectPreviousSession() {
        let ordered = allSessionIDsOrdered
        guard !ordered.isEmpty else { return }
        guard let current = selectedSessionID, let idx = ordered.firstIndex(of: current) else {
            selectedSessionID = ordered.first
            return
        }
        if idx > 0 {
            selectedSessionID = ordered[idx - 1]
        }
    }

    func selectNextSession() {
        let ordered = allSessionIDsOrdered
        guard !ordered.isEmpty else { return }
        guard let current = selectedSessionID, let idx = ordered.firstIndex(of: current) else {
            selectedSessionID = ordered.first
            return
        }
        if idx < ordered.count - 1 {
            selectedSessionID = ordered[idx + 1]
        }
    }

    /// Returns the next (or previous if last) sibling session ID within the same folder.
    private func nextSessionID(after id: UUID, inFolderOf session: TerminalSession) -> UUID? {
        guard let folder = folders.first(where: { $0.id == session.folderID }) else { return nil }
        let siblings = folder.sessionIDs.filter { $0 != id }
        if siblings.isEmpty {
            // Try sessions in other folders
            let allOther = allSessionIDsOrdered.filter { $0 != id }
            return allOther.first
        }
        // Prefer the next sibling, otherwise the previous
        if let idx = folder.sessionIDs.firstIndex(of: id) {
            if idx < folder.sessionIDs.count - 1 {
                return folder.sessionIDs[idx + 1]
            }
            if idx > 0 {
                return folder.sessionIDs[idx - 1]
            }
        }
        return siblings.first
    }

    /// Re-create tmux sessions that were killed externally while the app was not running.
    private func restoreTmuxSessions() {
        guard tmuxAvailable else { return }
        for session in sessions {
            let cwd = session.worktreePath ?? session.workingDirectory
            if !TmuxService.sessionExists(name: session.tmuxSessionName) {
                try? TmuxService.createSession(name: session.tmuxSessionName, cwd: cwd)
            }
        }
    }

    private func loadState() {
        do {
            let state = try PersistenceService.load()
            folders = state.folders
            sessions = state.sessions
        } catch {
            print("Failed to load state: \(error)")
        }
    }

    private func saveState() {
        do {
            try PersistenceService.save(folders: folders, sessions: sessions)
        } catch {
            print("Failed to save state: \(error)")
        }
    }
}
