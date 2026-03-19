import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var folders: [ManagedFolder] = []
    var sessions: [TerminalSession] = []
    var selectedSessionID: UUID?
    var tmuxAvailable: Bool = false

    let terminalManager = TerminalSessionManager()

    init() {
        tmuxAvailable = TmuxService.isAvailable()
        loadState()
    }

    var selectedSession: TerminalSession? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    func addFolder(path: String) {
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

        saveState()

        if selectedSessionID == nil {
            selectedSessionID = session.id
        }
    }

    func removeFolder(id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let folder = folders[index]

        // Remove all sessions belonging to this folder
        for sessionID in folder.sessionIDs {
            removeSession(id: sessionID, save: false)
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
        sessions.append(session)

        if let folderIndex = folders.firstIndex(where: { $0.id == folderID }) {
            folders[folderIndex].sessionIDs.append(session.id)
        }

        selectedSessionID = session.id
        saveState()
    }

    func removeSession(id: UUID, save: Bool = true) {
        if selectedSessionID == id {
            selectedSessionID = nil
        }
        terminalManager.destroyTerminal(for: id)
        sessions.removeAll { $0.id == id }

        // Remove from folder's sessionIDs
        for i in folders.indices {
            folders[i].sessionIDs.removeAll { $0 == id }
        }

        if save { saveState() }
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
