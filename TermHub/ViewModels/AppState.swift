import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var folders: [ManagedFolder] = []
    var sessions: [TerminalSession] = []
    var selectedSessionID: UUID? {
        didSet {
            if let id = selectedSessionID, NSApp.isActive {
                sessionsNeedingAttention.remove(id)
            }
        }
    }
    var tmuxAvailable: Bool = false
    var pendingWorktreeFolder: ManagedFolder?
    var pendingNewBranchFolder: ManagedFolder?
    var errorMessage: String?
    var showingAddFolder = false
    var showKeyboardShortcuts = false
    var showCommandPalette = false
    var sessionsNeedingAttention: Set<UUID> = [] {
        didSet {
            NSApp.dockTile.badgeLabel = sessionsNeedingAttention.isEmpty
                ? nil
                : "\(sessionsNeedingAttention.count)"
        }
    }
    private var lastBellTime: [UUID: Date] = [:]

    let terminalManager = TerminalSessionManager()

    init() {
        tmuxAvailable = TmuxService.isAvailable()
        loadState()
        migrateTmuxSessionNames()
        restoreTmuxSessions()

        terminalManager.onBell = { [weak self] sessionID in
            self?.markNeedsAttention(sessionID: sessionID)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if let id = self?.selectedSessionID {
                    self?.sessionsNeedingAttention.remove(id)
                }
            }
        }

        terminalManager.onTitleChange = { [weak self] sessionID, title in
            self?.handleTerminalTitleChange(sessionID: sessionID, title: title)
        }
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

        // tmux session is created lazily by TerminalSessionManager.startProcessIfNeeded
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
        let folderName = folders.first(where: { $0.id == folderID })?.name
        let session = TerminalSession(
            folderID: folderID,
            title: title,
            workingDirectory: cwd,
            worktreePath: worktreePath,
            branchName: branchName,
            folderName: folderName
        )

        // tmux session is created lazily by TerminalSessionManager.startProcessIfNeeded
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

        // Perform tmux + worktree cleanup (best-effort)
        do {
            try TmuxService.killSession(name: session.tmuxSessionName)
        } catch {
            print("[TermHub] Failed to kill tmux session '\(session.tmuxSessionName)': \(error)")
        }
        if let worktreePath = session.worktreePath {
            let folderPath = parentFolderPath ?? folders.first(where: { $0.id == session.folderID })?.path
            if let repoPath = folderPath {
                do {
                    try GitService.removeWorktree(repoPath: repoPath, worktreePath: worktreePath)
                } catch {
                    print("[TermHub] Failed to remove worktree '\(worktreePath)': \(error)")
                }
            }
        }

        // Auto-select next sibling before removing
        if selectedSessionID == id {
            selectedSessionID = nextSessionID(after: id, inFolderOf: session)
        }

        terminalManager.destroyTerminal(for: id)
        sessionsNeedingAttention.remove(id)
        lastBellTime.removeValue(forKey: id)
        sessions.removeAll { $0.id == id }

        // Remove from folder's sessionIDs
        for i in folders.indices {
            folders[i].sessionIDs.removeAll { $0 == id }
        }

        if save { saveState() }
    }

    /// Only applies the title if the user hasn't manually renamed the session.
    /// Ignores empty titles (e.g. sent by programs on exit) to avoid clearing useful titles.
    private func handleTerminalTitleChange(sessionID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let session = sessions.first(where: { $0.id == sessionID }),
              !session.hasCustomTitle
        else { return }
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].title = trimmed
        saveState()
    }

    func renameSession(id: UUID, newTitle: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = newTitle
        sessions[index].hasCustomTitle = true
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

    func markNeedsAttention(sessionID: UUID) {
        let isAppActive = NSApp.isActive
        guard !(selectedSessionID == sessionID && isAppActive) else { return }

        let now = Date()
        if let last = lastBellTime[sessionID], now.timeIntervalSince(last) < 2 {
            return
        }
        lastBellTime[sessionID] = now
        sessionsNeedingAttention.insert(sessionID)
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

    /// Migrate tmux session names from the old scheme (allowing `.` and `:`) to the new
    /// sanitized scheme (replacing them with `_`). Renames live tmux sessions and updates
    /// the persisted model so existing sessions are not orphaned.
    private func migrateTmuxSessionNames() {
        guard tmuxAvailable else { return }
        var changed = false
        for i in sessions.indices {
            let oldName = sessions[i].tmuxSessionName
            let newName = oldName
                .replacingOccurrences(of: ".", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            guard newName != oldName else { continue }
            if TmuxService.sessionExists(name: oldName) {
                do {
                    try TmuxService.renameSession(oldName: oldName, newName: newName)
                } catch {
                    print("[TermHub] Failed to rename tmux session '\(oldName)' → '\(newName)': \(error)")
                }
            }
            sessions[i].tmuxSessionName = newName
            changed = true
        }
        if changed { saveState() }
    }

    /// Re-create tmux sessions that were killed externally while the app was not running.
    private func restoreTmuxSessions() {
        guard tmuxAvailable else { return }
        for session in sessions {
            let cwd = session.worktreePath ?? session.workingDirectory
            if !TmuxService.sessionExists(name: session.tmuxSessionName) {
                do {
                    try TmuxService.createSession(name: session.tmuxSessionName, cwd: cwd)
                } catch {
                    print("[TermHub] Failed to restore tmux session '\(session.tmuxSessionName)': \(error)")
                }
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
