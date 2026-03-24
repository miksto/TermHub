import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var folders: [ManagedFolder] = []
    @ObservationIgnored var sessions: [TerminalSession] = []
    @ObservationIgnored private var displayStates: [UUID: SessionDisplayState] = [:]

    func displayState(for id: UUID) -> SessionDisplayState? {
        displayStates[id]
    }
    var selectedSessionID: UUID? {
        didSet {
            if let id = selectedSessionID, NSApp?.isActive == true {
                sessionsNeedingAttention.remove(id)
            }
            if let id = selectedSessionID, !isSessionSwitcherActive {
                updateMRUOrder(selectedID: id)
            }
            if !isLoading, selectedSessionID != nil {
                saveState()
            }
        }
    }
    private(set) var sessionMRUOrder: [UUID] = []
    var isSessionSwitcherActive = false
    var switcherSelectedIndex: Int = 0
    var tmuxAvailable: Bool = false
    var pendingWorktreeFolder: ManagedFolder?
    var pendingNewBranchFolder: ManagedFolder?
    var pendingWorktreeSandbox: Bool = false
    var errorMessage: String?
    var pendingRemoveFolderID: UUID?
    var pendingSandboxConfigFolderID: UUID?
    var showKeyboardShortcuts = false
    var showCommandPalette = false
    /// Incremented only when sessions are added or removed (not on title/property changes).
    /// Used by TerminalContainerView to avoid re-evaluation on every session mutation.
    private(set) var sessionListVersion = 0
    var renamingSessionID: UUID?
    var renamingEditText: String = ""
    var sessionsNeedingAttention: Set<UUID> = [] {
        didSet {
            NSApp.dockTile.badgeLabel = sessionsNeedingAttention.isEmpty
                ? nil
                : "\(sessionsNeedingAttention.count)"
        }
    }
    var gitStatuses: [String: GitStatus] = [:]
    var detailTabBySession: [UUID: DetailTab] = [:]
    var showSandboxManager = false
    var sandboxes: [SandboxInfo] = []
    var sandboxOperationInProgress: Set<String> = []
    private var sandboxRefreshTimer: Timer?
    var currentDiff: GitDiff?
    var isDiffLoading = false
    @ObservationIgnored private let gitFileWatcher = GitFileWatcher()
    private var lastBellTime: [UUID: Date] = [:]
    private var isLoading = false
    private var loadFailed = false
    @ObservationIgnored private var debouncedSaveWorkItem: DispatchWorkItem?

    let terminalManager = TerminalSessionManager()

    init() {
        tmuxAvailable = TmuxService.isAvailable()
        loadState()
        detectGitRepos()
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

        refreshGitStatuses()
        updateGitFileWatcher()
        refreshSandboxes()
        startSandboxPolling()
    }

    var selectedSession: TerminalSession? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    /// All sessions ordered by folder for keyboard navigation (matches sidebar visual order).
    var allSessionIDsOrdered: [UUID] {
        folders.flatMap { folder in
            let validIDs = folder.sessionIDs.filter { id in sessions.contains { $0.id == id } }
            let plain = validIDs.filter { id in
                sessions.first(where: { $0.id == id })?.worktreePath == nil
            }
            var seenWorktrees: [String: [UUID]] = [:]
            var worktreeOrder: [String] = []
            for id in validIDs {
                guard let session = sessions.first(where: { $0.id == id }),
                      let wt = session.worktreePath else { continue }
                if seenWorktrees[wt] == nil {
                    worktreeOrder.append(wt)
                }
                seenWorktrees[wt, default: []].append(id)
            }
            let worktree = worktreeOrder.flatMap { seenWorktrees[$0] ?? [] }
            return plain + worktree
        }
    }

    func showAddFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            addFolder(path: url.path)
        }
    }

    func addFolder(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            errorMessage = "Folder path does not exist: \(path)"
            return
        }

        // User is intentionally adding data — clear the load-failure guard so saves work again.
        loadFailed = false

        let folder = ManagedFolder(path: path)
        folders.append(folder)

        // Auto-create a default session for the folder
        let session = TerminalSession(
            folderID: folder.id,
            title: folder.name,
            workingDirectory: path
        )
        sessions.append(session)
        displayStates[session.id] = SessionDisplayState(title: session.title)
        sessionMRUOrder.insert(session.id, at: 0)
        var updated = folders[folders.count - 1]
        updated.sessionIDs.append(session.id)
        folders[folders.count - 1] = updated

        // tmux session is created lazily by TerminalSessionManager.startProcessIfNeeded
        sessionListVersion += 1
        saveState()

        updateGitFileWatcher()

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
        updateGitFileWatcher()
    }

    func addSession(
        folderID: UUID,
        title: String,
        cwd: String,
        worktreePath: String? = nil,
        branchName: String? = nil,
        isExternalWorktree: Bool = false,
        ownsBranch: Bool = false,
        isSandboxSession: Bool = false
    ) {
        let folderName = folders.first(where: { $0.id == folderID })?.name
        let session = TerminalSession(
            folderID: folderID,
            title: title,
            workingDirectory: cwd,
            worktreePath: worktreePath,
            branchName: branchName,
            isExternalWorktree: isExternalWorktree,
            ownsBranch: ownsBranch,
            isSandboxSession: isSandboxSession,
            folderName: folderName
        )

        // tmux session is created lazily by TerminalSessionManager.startProcessIfNeeded
        sessions.append(session)
        displayStates[session.id] = SessionDisplayState(title: session.title)
        sessionMRUOrder.insert(session.id, at: 0)

        if let folderIndex = folders.firstIndex(where: { $0.id == folderID }) {
            folders[folderIndex].sessionIDs.append(session.id)
        }

        selectedSessionID = session.id
        sessionListVersion += 1
        saveState()
        if worktreePath != nil {
            updateGitFileWatcher()
        }
    }

    func removeSession(id: UUID, parentFolderPath: String? = nil, save: Bool = true) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }

        // Capture cleanup info before mutating state
        let tmuxName = session.tmuxSessionName
        let worktreePath = session.worktreePath
        let isExternal = session.isExternalWorktree
        let ownsBranch = session.ownsBranch
        let branchName = session.branchName
        let otherSessionUsesWorktree = sessions.contains {
            $0.id != id && $0.worktreePath == worktreePath
        }
        let repoPath = parentFolderPath ?? folders.first(where: { $0.id == session.folderID })?.path

        // UI state mutations (stay on MainActor)
        if selectedSessionID == id {
            selectedSessionID = nextSessionID(after: id, inFolderOf: session)
        }

        terminalManager.destroyTerminal(for: id)
        sessionsNeedingAttention.remove(id)
        lastBellTime.removeValue(forKey: id)
        displayStates.removeValue(forKey: id)
        sessionMRUOrder.removeAll { $0 == id }
        sessions.removeAll { $0.id == id }

        for i in folders.indices {
            folders[i].sessionIDs.removeAll { $0 == id }
        }

        sessionListVersion += 1
        if save { saveState() }
        if worktreePath != nil {
            updateGitFileWatcher()
        }

        // Background cleanup (blocking I/O — best-effort)
        Task.detached {
            do { try TmuxService.killSession(name: tmuxName) }
            catch { print("[TermHub] Failed to kill tmux session '\(tmuxName)': \(error)") }

            if let worktreePath, !isExternal, !otherSessionUsesWorktree, let repoPath {
                do { try GitService.removeWorktree(repoPath: repoPath, worktreePath: worktreePath) }
                catch { print("[TermHub] Failed to remove worktree '\(worktreePath)': \(error)") }

                if ownsBranch, let branchName {
                    do { try GitService.deleteLocalBranch(repoPath: repoPath, branch: branchName) }
                    catch { print("[TermHub] Failed to delete branch '\(branchName)': \(error)") }
                }

                let container = GitService.worktreeContainerPath(repoPath: repoPath)
                let fm = FileManager.default
                if let contents = try? fm.contentsOfDirectory(atPath: container), contents.isEmpty {
                    try? fm.removeItem(atPath: container)
                }
            }
        }
    }

    /// Only applies the title if the user hasn't manually renamed the session.
    /// Ignores empty titles (e.g. sent by programs on exit) to avoid clearing useful titles.
    /// Skips updates while the user is actively renaming the session or if the title is unchanged.
    private func handleTerminalTitleChange(sessionID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              renamingSessionID != sessionID,
              let session = sessions.first(where: { $0.id == sessionID }),
              !session.hasCustomTitle
        else { return }
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[index].title != trimmed else { return }
        sessions[index].title = trimmed
        displayStates[sessionID]?.title = trimmed
        scheduleSave()
    }

    func startRenamingSession(id: UUID) {
        if let session = sessions.first(where: { $0.id == id }) {
            renamingEditText = session.title
        }
        renamingSessionID = id
    }

    func finishRenamingSession(id: UUID) {
        if renamingSessionID == id {
            renamingSessionID = nil
            renamingEditText = ""
        }
    }

    func setSandboxName(_ name: String?, forFolder folderID: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].sandboxName = name
        saveState()
        refreshSandboxes()
    }

    // MARK: - Sandbox Lifecycle

    func sandboxInfo(forFolderID folderID: UUID) -> SandboxInfo? {
        guard let folder = folders.first(where: { $0.id == folderID }),
              let name = folder.sandboxName else { return nil }
        return sandboxes.first { $0.name == name }
    }

    func refreshSandboxes() {
        Task.detached {
            let list = DockerSandboxService.listSandboxes()
            await MainActor.run { [weak self] in
                self?.sandboxes = list
            }
        }
    }

    func createSandbox(name: String, workspacePath: String) {
        createSandbox(name: name, workspaces: [workspacePath])
    }

    func createSandbox(name: String, workspaces: [String]) {
        sandboxOperationInProgress.insert(name)
        Task.detached {
            do {
                try DockerSandboxService.createSandbox(name: name, workspaces: workspaces)
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Failed to create sandbox: \(msg)"
                }
            }
            let list = DockerSandboxService.listSandboxes()
            await MainActor.run { [weak self] in
                self?.sandboxes = list
                self?.sandboxOperationInProgress.remove(name)
            }
        }
    }


    func stopSandbox(name: String) {
        sandboxOperationInProgress.insert(name)
        Task.detached {
            do {
                try DockerSandboxService.stopSandbox(name: name)
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Failed to stop sandbox: \(msg)"
                }
            }
            let list = DockerSandboxService.listSandboxes()
            await MainActor.run { [weak self] in
                self?.sandboxes = list
                self?.sandboxOperationInProgress.remove(name)
            }
        }
    }

    func removeSandbox(name: String) {
        sandboxOperationInProgress.insert(name)
        Task.detached {
            do {
                try DockerSandboxService.removeSandbox(name: name)
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Failed to remove sandbox: \(msg)"
                }
            }
            let list = DockerSandboxService.listSandboxes()
            await MainActor.run { [weak self] in
                self?.sandboxes = list
                self?.sandboxOperationInProgress.remove(name)
            }
        }
    }

    private func startSandboxPolling() {
        sandboxRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.folders.contains(where: { $0.hasSandbox }) else { return }
                self.refreshSandboxes()
            }
        }
    }

    func moveFolder(fromOffsets source: IndexSet, toOffset destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
        saveState()
    }


    func renameSession(id: UUID, newTitle: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = newTitle
        displayStates[id]?.title = newTitle
        sessions[index].hasCustomTitle = true
        displayStates[id]?.title = newTitle
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

    func selectSessionByIndex(_ index: Int) {
        let ordered = allSessionIDsOrdered
        guard index >= 0, index < ordered.count else { return }
        selectedSessionID = ordered[index]
    }

    func selectNextSessionNeedingAttention() {
        guard !sessionsNeedingAttention.isEmpty else { return }
        let ordered = allSessionIDsOrdered.filter { sessionsNeedingAttention.contains($0) }
        guard !ordered.isEmpty else { return }

        if let current = selectedSessionID, let idx = ordered.firstIndex(of: current) {
            // Cycle to next attention session after current
            selectedSessionID = ordered[(idx + 1) % ordered.count]
        } else if let current = selectedSessionID,
                  let currentGlobal = allSessionIDsOrdered.firstIndex(of: current) {
            // Pick the first attention session after the current position
            selectedSessionID = ordered.first { id in
                guard let idx = allSessionIDsOrdered.firstIndex(of: id) else { return false }
                return idx > currentGlobal
            } ?? ordered.first
        } else {
            selectedSessionID = ordered.first
        }
    }

    // MARK: - MRU Session Switcher

    private func updateMRUOrder(selectedID: UUID) {
        sessionMRUOrder.removeAll { $0 == selectedID }
        sessionMRUOrder.insert(selectedID, at: 0)
    }

    /// Sessions in MRU order with display info for the switcher overlay.
    var sessionSwitcherItems: [(id: UUID, title: String, folderName: String?)] {
        let validIDs = sessionMRUOrder.filter { id in sessions.contains { $0.id == id } }
        return validIDs.compactMap { id in
            guard let session = sessions.first(where: { $0.id == id }) else { return nil }
            let folder = folders.first { $0.id == session.folderID }
            return (id: id, title: displayState(for: id)?.title ?? session.title, folderName: folder?.name)
        }
    }

    func beginSessionSwitcher() {
        let items = sessionSwitcherItems
        guard items.count >= 2 else { return }
        isSessionSwitcherActive = true
        switcherSelectedIndex = 1
    }

    func advanceSessionSwitcher() {
        let items = sessionSwitcherItems
        guard !items.isEmpty else { return }
        switcherSelectedIndex = (switcherSelectedIndex + 1) % items.count
    }

    func reverseSessionSwitcher() {
        let items = sessionSwitcherItems
        guard !items.isEmpty else { return }
        switcherSelectedIndex = (switcherSelectedIndex - 1 + items.count) % items.count
    }

    func commitSessionSwitcher() {
        let items = sessionSwitcherItems
        let index = switcherSelectedIndex
        isSessionSwitcherActive = false
        if index < items.count {
            selectedSessionID = items[index].id
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

    /// Re-create tmux sessions that were killed externally while the app was not running,
    /// and kill orphaned tmux sessions that no longer have a matching app session.
    private func restoreTmuxSessions() {
        guard tmuxAvailable else { return }
        let sessionsSnapshot = sessions.map { session -> (name: String, cwd: String, shellCommand: String?) in
            let cwd = session.worktreePath ?? session.workingDirectory
            let shellCommand: String? = if session.isSandboxSession,
                let folder = folders.first(where: { $0.id == session.folderID }),
                let sandboxName = folder.sandboxName {
                DockerSandboxService.execCommand(sandboxName: sandboxName, cwd: cwd)
            } else {
                nil
            }
            return (name: session.tmuxSessionName, cwd: cwd, shellCommand: shellCommand)
        }
        let knownNames = Set(sessionsSnapshot.map(\.name))
        Task.detached {
            // Restore missing sessions
            for session in sessionsSnapshot {
                if !TmuxService.sessionExists(name: session.name) {
                    do {
                        try TmuxService.createSession(name: session.name, cwd: session.cwd, shellCommand: session.shellCommand)
                    } catch {
                        print("[TermHub] Failed to restore tmux session '\(session.name)': \(error)")
                    }
                }
            }

            // Kill orphaned sessions on the termhub socket
            let allTmuxSessions = TmuxService.listSessions()
            let orphans = allTmuxSessions.filter { !knownNames.contains($0) }
            if !orphans.isEmpty {
                print("[TermHub] Cleaning up \(orphans.count) orphaned tmux session(s)")
                for name in orphans {
                    do { try TmuxService.killSession(name: name) }
                    catch { print("[TermHub] Failed to kill orphaned session '\(name)': \(error)") }
                }
            }
        }
    }

    func gitStatus(forFolderPath path: String) -> GitStatus? {
        gitStatuses[path]
    }

    func gitStatus(forSession session: TerminalSession) -> GitStatus? {
        if let worktreePath = session.worktreePath {
            return gitStatuses[worktreePath]
        }
        guard let folder = folders.first(where: { $0.id == session.folderID }) else { return nil }
        return gitStatuses[folder.path]
    }

    var folderForSelectedSession: ManagedFolder? {
        guard let session = selectedSession,
              let folder = folders.first(where: { $0.id == session.folderID })
        else { return nil }
        return folder
    }

    var currentDetailTab: DetailTab {
        guard let id = selectedSessionID else { return .terminal }
        return detailTabBySession[id] ?? .terminal
    }

    func setDetailTab(_ tab: DetailTab, for sessionID: UUID) {
        detailTabBySession[sessionID] = tab
        if tab == .gitDiff {
            loadDiffForCurrentSession()
        }
    }

    func toggleDetailTab() {
        guard let id = selectedSessionID,
              folderForSelectedSession?.isGitRepo == true else { return }
        let current = detailTabBySession[id] ?? .terminal
        setDetailTab(current == .terminal ? .gitDiff : .terminal, for: id)
    }

    func selectPreviousDetailTab() {
        guard let id = selectedSessionID else { return }
        let current = detailTabBySession[id] ?? .terminal
        if current == .gitDiff {
            setDetailTab(.terminal, for: id)
        }
    }

    func selectNextDetailTab() {
        guard let id = selectedSessionID,
              folderForSelectedSession?.isGitRepo == true else { return }
        let current = detailTabBySession[id] ?? .terminal
        if current == .terminal {
            setDetailTab(.gitDiff, for: id)
        }
    }

    func loadDiffForCurrentSession() {
        guard let session = selectedSession else { return }
        let path = session.worktreePath
            ?? folders.first(where: { $0.id == session.folderID })?.path
        guard let workingDir = path else { return }

        isDiffLoading = true
        Task.detached {
            let raw = GitService.diff(path: workingDir)
            let diff = GitService.parseDiff(raw)
            await MainActor.run { [weak self] in
                self?.currentDiff = diff
                self?.isDiffLoading = false
                NotificationCenter.default.post(name: .diffDataDidChange, object: nil)
            }
        }
    }

    /// Updates the set of `.git` directories being watched for filesystem changes.
    /// Call this whenever folders or worktree sessions are added/removed.
    func updateGitFileWatcher() {
        var paths: [String] = []
        for folder in folders where folder.isGitRepo && folder.pathExists {
            paths.append(folder.path)
        }
        for session in sessions {
            if let worktreePath = session.worktreePath {
                paths.append(worktreePath)
            }
        }
        gitFileWatcher.start(paths: paths) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshGitStatuses()
                if self?.currentDetailTab == .gitDiff {
                    self?.loadDiffForCurrentSession()
                }
            }
        }
    }

    private func refreshGitStatuses() {
        var pathsToCheck: [String] = []
        for folder in folders where folder.isGitRepo && folder.pathExists {
            pathsToCheck.append(folder.path)
        }
        for session in sessions {
            if let worktreePath = session.worktreePath {
                pathsToCheck.append(worktreePath)
            }
        }
        guard !pathsToCheck.isEmpty else { return }

        let paths = pathsToCheck
        Task.detached {
            // Run git status calls in parallel instead of sequentially.
            var statuses: [String: GitStatus] = [:]
            await withTaskGroup(of: (String, GitStatus).self) { group in
                for path in paths {
                    group.addTask { (path, GitService.status(path: path)) }
                }
                for await (path, status) in group {
                    statuses[path] = status
                }
            }
            let result = statuses
            await MainActor.run { @MainActor [weak self] in
                guard let self else { return }
                // Only update entries that changed to avoid unnecessary observation triggers.
                var changed = false
                for (path, status) in result {
                    if self.gitStatuses[path] != status {
                        self.gitStatuses[path] = status
                        changed = true
                    }
                }
                // Remove stale entries for paths no longer tracked.
                for key in self.gitStatuses.keys where result[key] == nil {
                    self.gitStatuses.removeValue(forKey: key)
                    changed = true
                }
                _ = changed
            }
        }
    }

    /// Detects git repo status for folders that don't have it persisted yet.
    /// Runs detection off the main thread to avoid blocking the UI at startup.
    private func detectGitRepos() {
        let foldersNeedingDetection = folders.enumerated().filter { !$0.element.isGitRepo && $0.element.pathExists }
        guard !foldersNeedingDetection.isEmpty else { return }

        let paths = foldersNeedingDetection.map { (index: $0.offset, path: $0.element.path) }
        Task.detached {
            var results: [(index: Int, isGit: Bool)] = []
            for item in paths {
                let isGit = GitService.isGitRepo(path: item.path)
                if isGit {
                    results.append((index: item.index, isGit: true))
                }
            }
            let detected = results
            await MainActor.run { [weak self] in
                guard let self else { return }
                var changed = false
                for result in detected {
                    guard result.index < self.folders.count,
                          self.folders[result.index].path == paths[result.index].path
                    else { continue }
                    self.folders[result.index].isGitRepo = true
                    changed = true
                }
                if changed { self.saveState() }
            }
        }
    }

    private func loadState() {
        isLoading = true
        defer { isLoading = false }
        do {
            let state = try PersistenceService.load()
            folders = state.folders
            sessions = state.sessions
            for session in sessions {
                displayStates[session.id] = SessionDisplayState(title: session.title)
            }
            // Restore MRU order, falling back to sidebar order for sessions not in the persisted list.
            let validSessionIDs = Set(sessions.map(\.id))
            let persisted = state.sessionMRUOrder.filter { validSessionIDs.contains($0) }
            let missing = allSessionIDsOrdered.filter { !persisted.contains($0) }
            sessionMRUOrder = persisted + missing
            selectedSessionID = state.selectedSessionID
            sessionListVersion += 1
        } catch {
            loadFailed = true
            errorMessage = "Failed to load saved state: \(error.localizedDescription). "
                + "A backup may exist at state.json.bak in Application Support/TermHub."
            print("Failed to load state: \(error)")
        }
    }

    private func saveState() {
        guard !loadFailed else { return }
        // Snapshot data on the main thread, then encode + write on a background queue.
        let state = PersistedState(
            folders: folders,
            sessions: sessions,
            selectedSessionID: selectedSessionID,
            sessionMRUOrder: sessionMRUOrder
        )
        PersistenceService.writeQueue.async {
            do {
                try PersistenceService.save(state: state)
            } catch {
                print("Failed to save state: \(error)")
            }
        }
    }

    /// Debounced save for high-frequency changes like terminal title updates.
    private func scheduleSave() {
        debouncedSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.saveState()
            }
        }
        debouncedSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
}
