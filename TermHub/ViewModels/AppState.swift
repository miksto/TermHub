import AppKit
import Carbon
import Foundation
import Observation

enum AssistantProvider: String, CaseIterable, Codable, Sendable {
    case claude
    case copilot

    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .copilot:
            return "GitHub Copilot"
        }
    }
}

@Observable
@MainActor
final class AppState {
    private static let assistantAllowedToolsByProviderUserDefaultsKey = "assistantAllowedToolsByProvider"
    private static let legacyAssistantAllowedToolsUserDefaultsKey = "assistantAllowedTools"
    private static let assistantModelByProviderUserDefaultsKey = "assistantModelByProvider"
    private static let assistantEffortByProviderUserDefaultsKey = "assistantEffortByProvider"

    private static func defaultAssistantAllowedTools(for provider: AssistantProvider) -> String {
        switch provider {
        case .claude:
            return "WebFetch,mcp__termhub__*"
        case .copilot:
            return "WebFetch"
        }
    }

    static func defaultAssistantModel(for provider: AssistantProvider) -> String {
        switch provider {
        case .claude: return "default"
        case .copilot: return "claude-haiku-4.5"
        }
    }

    static func assistantModelDisplayName(for provider: AssistantProvider, model: String) -> String {
        guard provider == .claude else { return model }
        switch model {
        case "default": return "Default (recommended) · Opus 4.6 · 1M context"
        case "sonnet": return "Sonnet · Sonnet 4.6"
        case "sonnet-1m": return "Sonnet (1M context) · Sonnet 4.6"
        case "haiku": return "Haiku · Haiku 4.5"
        default: return model
        }
    }

    static func assistantModelOptions(for provider: AssistantProvider) -> [String] {
        switch provider {
        case .claude:
            return ["default", "sonnet", "sonnet-1m", "haiku"]
        case .copilot:
            return [
                "claude-sonnet-4.6",
                "claude-sonnet-4.5",
                "claude-haiku-4.5",
                "claude-opus-4.6",
                "claude-opus-4.5",
                "claude-sonnet-4",
                "gpt-5.4",
                "gpt-5.3-codex",
                "gpt-5.2-codex",
                "gpt-5.2",
                "gpt-5.1-codex-max",
                "gpt-5.1-codex",
                "gpt-5.1",
                "gpt-5.1-codex-mini",
                "gpt-5-mini",
                "gpt-4.1",
            ]
        }
    }

    static func defaultAssistantEffort(for provider: AssistantProvider) -> String {
        switch provider {
        case .claude: return "low"
        case .copilot: return ""
        }
    }

    static func assistantEffortOptions(for provider: AssistantProvider) -> [String] {
        switch provider {
        case .claude, .copilot:
            return ["", "low", "medium", "high", "xhigh"]
        }
    }

    static func supportsAssistantEffort(for provider: AssistantProvider, model: String) -> Bool {
        switch provider {
        case .claude:
            return model != "haiku"
        case .copilot:
            let supportingModels: Set<String> = [
                "gpt-5.4",
                "gpt-5.3-codex",
                "gpt-5.2-codex",
                "gpt-5.2",
                "gpt-5.1-codex-max",
                "gpt-5.1-codex",
                "gpt-5.1",
                "gpt-5.1-codex-mini",
            ]
            return supportingModels.contains(model)
        }
    }

    private static func normalizedAssistantModel(_ value: String, for provider: AssistantProvider) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard assistantModelOptions(for: provider).contains(trimmed) else {
            return defaultAssistantModel(for: provider)
        }
        return trimmed
    }

    private static func normalizedAssistantEffort(_ value: String, for provider: AssistantProvider) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard assistantEffortOptions(for: provider).contains(trimmed) else {
            return defaultAssistantEffort(for: provider)
        }
        return trimmed
    }

    private static func normalizedAssistantModelByProvider(_ raw: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for provider in AssistantProvider.allCases {
            let key = provider.rawValue
            let value = raw[key] ?? defaultAssistantModel(for: provider)
            normalized[key] = normalizedAssistantModel(value, for: provider)
        }
        return normalized
    }

    private static func normalizedAssistantEffortByProvider(_ raw: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for provider in AssistantProvider.allCases {
            let key = provider.rawValue
            let value = raw[key] ?? defaultAssistantEffort(for: provider)
            normalized[key] = normalizedAssistantEffort(value, for: provider)
        }
        return normalized
    }

    private static func normalizedAssistantAllowedToolsByProvider(_ raw: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for provider in AssistantProvider.allCases {
            if let value = raw[provider.rawValue] {
                normalized[provider.rawValue] = value
            } else {
                normalized[provider.rawValue] = defaultAssistantAllowedTools(for: provider)
            }
        }
        return normalized
    }

    private static func loadAssistantAllowedToolsByProviderFromUserDefaults() -> [String: String] {
        if let stored = UserDefaults.standard.dictionary(forKey: assistantAllowedToolsByProviderUserDefaultsKey) as? [String: String] {
            return normalizedAssistantAllowedToolsByProvider(stored)
        }

        var migrated = normalizedAssistantAllowedToolsByProvider([:])
        if let legacy = UserDefaults.standard.string(forKey: legacyAssistantAllowedToolsUserDefaultsKey),
           !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            // Keep legacy behavior for Claude while keeping Copilot on a safe default.
            migrated[AssistantProvider.claude.rawValue] = legacy
        }
        UserDefaults.standard.set(migrated, forKey: assistantAllowedToolsByProviderUserDefaultsKey)
        return migrated
    }

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
    var errorMessage: String?
    var pendingRemoveFolderID: UUID?
    var showKeyboardShortcuts = false
    var showSettings = false
    var pendingSandboxPickerContext: SandboxPickerContext?
    var pendingWorktreeSandbox: String?
    var pendingNewBranchSandbox: String?
    var lastUsedSandboxName: String?
    var showAssistant = false
    var assistantMessages: [AssistantMessage] = []
    var assistantInputText = ""
    var assistantIsBusy = false
    var assistantStatusMessage: String?
    var assistantProvider: AssistantProvider {
        didSet {
            UserDefaults.standard.set(assistantProvider.rawValue, forKey: "assistantProvider")
            guard oldValue != assistantProvider else { return }
            assistantService.stop()
            activeAssistantMessageID = nil
            assistantIsBusy = false
            assistantStatusMessage = nil
            appendAssistantSystemMessage("Assistant provider switched to \(assistantProvider.displayName).")
        }
    }

    struct SandboxPickerContext {
        let folderID: UUID
        let folderName: String
        let cwd: String
        let worktreePath: String?
        let branchName: String?
    }
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
    /// Per-sandbox environment variable names to forward from the host into sandbox shells.
    var sandboxEnvironmentKeys: [String: [String]] = [:]
    private var sandboxRefreshTimer: Timer?
    var currentDiff: GitDiff?
    var isDiffLoading = false
    @ObservationIgnored private let gitFileWatcher = GitFileWatcher()
    private var lastBellTime: [UUID: Date] = [:]
    private var isLoading = false
    private var loadFailed = false
    @ObservationIgnored private var debouncedSaveWorkItem: DispatchWorkItem?
    @ObservationIgnored private let persistence: StatePersistence
    @ObservationIgnored private var ipcServer: IPCServer?
    @ObservationIgnored private let assistantService = AssistantService()
    @ObservationIgnored private var activeAssistantMessageID: UUID?
    @ObservationIgnored private var assistantIdleWorkItem: DispatchWorkItem?
    @ObservationIgnored private var surfacedAssistantNotices: Set<String> = []
    @ObservationIgnored private var assistantErrorBuffer = ""

    var optionAsMetaKey: Bool {
        didSet {
            UserDefaults.standard.set(optionAsMetaKey, forKey: "optionAsMetaKey")
            UserDefaults.standard.set(true, forKey: "optionAsMetaKeyIsSet")
            terminalManager.updateOptionAsMetaKey(optionAsMetaKey)
        }
    }

    var copyClaudeSettingsToWorktrees: Bool {
        didSet {
            UserDefaults.standard.set(copyClaudeSettingsToWorktrees, forKey: "copyClaudeSettingsToWorktrees")
        }
    }

    var assistantAllowedToolsByProvider: [String: String] {
        didSet {
            UserDefaults.standard.set(
                Self.normalizedAssistantAllowedToolsByProvider(assistantAllowedToolsByProvider),
                forKey: Self.assistantAllowedToolsByProviderUserDefaultsKey
            )
        }
    }

    var assistantAllowedTools: String {
        get {
            assistantAllowedToolsByProvider[assistantProvider.rawValue]
                ?? Self.defaultAssistantAllowedTools(for: assistantProvider)
        }
        set {
            assistantAllowedToolsByProvider[assistantProvider.rawValue] = newValue
        }
    }

    var assistantModelByProvider: [String: String] {
        didSet {
            UserDefaults.standard.set(
                Self.normalizedAssistantModelByProvider(assistantModelByProvider),
                forKey: Self.assistantModelByProviderUserDefaultsKey
            )
        }
    }

    var assistantModel: String {
        get {
            let value = assistantModelByProvider[assistantProvider.rawValue]
                ?? Self.defaultAssistantModel(for: assistantProvider)
            return Self.normalizedAssistantModel(value, for: assistantProvider)
        }
        set {
            assistantModelByProvider[assistantProvider.rawValue] = Self.normalizedAssistantModel(newValue, for: assistantProvider)
        }
    }

    var assistantEffortByProvider: [String: String] {
        didSet {
            UserDefaults.standard.set(
                Self.normalizedAssistantEffortByProvider(assistantEffortByProvider),
                forKey: Self.assistantEffortByProviderUserDefaultsKey
            )
        }
    }

    var assistantEffort: String {
        get {
            let value = assistantEffortByProvider[assistantProvider.rawValue]
                ?? Self.defaultAssistantEffort(for: assistantProvider)
            return Self.normalizedAssistantEffort(value, for: assistantProvider)
        }
        set {
            assistantEffortByProvider[assistantProvider.rawValue] = Self.normalizedAssistantEffort(newValue, for: assistantProvider)
        }
    }

    var assistantModelSupportsEffort: Bool {
        Self.supportsAssistantEffort(for: assistantProvider, model: assistantModel)
    }

    var mcpServerEnabled: Bool {
        didSet {
            UserDefaults.standard.set(mcpServerEnabled, forKey: "mcpServerEnabled")
            if mcpServerEnabled {
                startIPCServer()
            } else {
                stopIPCServer()
            }
        }
    }

    var assistantConnectedText: String {
        "Connected to \(assistantProvider.displayName)"
    }

    var assistantRespondingText: String {
        "\(assistantProvider.displayName) is responding…"
    }

    var assistantPromptPlaceholder: String {
        "Prompt \(assistantProvider.displayName)…"
    }

    var assistantAllowedToolsPlaceholder: String {
        switch assistantProvider {
        case .claude:
            return "e.g. WebFetch,mcp__termhub__*"
        case .copilot:
            return "e.g. WebFetch,bash"
        }
    }

    var assistantAllowedToolsHelpText: String {
        switch assistantProvider {
        case .claude:
            return "Claude-only setting. Comma-separated tools for Claude `--allowedTools`."
        case .copilot:
            return "Copilot-only setting. Use concrete tool names only (no wildcards like `*`)."
        }
    }

    var assistantEmptyStateText: String {
        switch assistantProvider {
        case .claude:
            return "Ask anything. Claude can use the TermHub MCP server to manage sessions, worktrees, and sandboxes."
        case .copilot:
            return "Ask anything. Copilot can use the TermHub MCP server when enabled. If responses fail, verify Copilot Allowed Tools use concrete names (no wildcards)."
        }
    }

    let terminalManager = TerminalSessionManager()

    init(persistence: StatePersistence? = nil) {
        let isTestHost = ProcessInfo.processInfo.isRunningTests
        self.persistence = persistence ?? (isTestHost ? NullPersistence() : DiskPersistence())
        if UserDefaults.standard.bool(forKey: "optionAsMetaKeyIsSet") {
            optionAsMetaKey = UserDefaults.standard.bool(forKey: "optionAsMetaKey")
        } else {
            optionAsMetaKey = Self.detectUSKeyboardLayout()
        }
        copyClaudeSettingsToWorktrees = UserDefaults.standard.object(forKey: "copyClaudeSettingsToWorktrees") as? Bool ?? true
        assistantProvider = AssistantProvider(rawValue: UserDefaults.standard.string(forKey: "assistantProvider") ?? "") ?? .claude
        assistantAllowedToolsByProvider = Self.loadAssistantAllowedToolsByProviderFromUserDefaults()
        assistantModelByProvider = Self.normalizedAssistantModelByProvider(
            UserDefaults.standard.dictionary(forKey: Self.assistantModelByProviderUserDefaultsKey) as? [String: String] ?? [:]
        )
        assistantEffortByProvider = Self.normalizedAssistantEffortByProvider(
            UserDefaults.standard.dictionary(forKey: Self.assistantEffortByProviderUserDefaultsKey) as? [String: String] ?? [:]
        )
        mcpServerEnabled = UserDefaults.standard.object(forKey: "mcpServerEnabled") as? Bool ?? true
        terminalManager.optionAsMetaKey = optionAsMetaKey
        tmuxAvailable = isTestHost ? false : TmuxService.isAvailable()
        loadState()
        configureAssistantService()
        if !isTestHost {
            detectGitRepos()
            restoreTmuxSessions()
        }

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

        if !isTestHost {
            refreshGitStatuses()
            updateGitFileWatcher()
            refreshSandboxes()
            startSandboxPolling()

            if mcpServerEnabled {
                startIPCServer()
            }
        }
    }

    deinit {
        assistantService.stop()
    }

    private func startIPCServer() {
        guard ipcServer == nil else { return }
        let server = IPCServer(appState: self)
        server.start()
        ipcServer = server
    }

    private func stopIPCServer() {
        ipcServer?.stop()
        ipcServer = nil
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

    func toggleAssistant() {
        showAssistant.toggle()
    }

    func appendAssistantSystemMessage(_ content: String) {
        assistantMessages.append(AssistantMessage(role: .system, content: content))
        scheduleSave()
    }

    func clearAssistantChat() {
        assistantService.stop()
        assistantService.resetAllSessionIDs()
        surfacedAssistantNotices.removeAll()
        assistantErrorBuffer = ""
        assistantMessages.removeAll()
        activeAssistantMessageID = nil
        assistantIsBusy = false
        assistantStatusMessage = nil
        saveState()
    }

    func restartAssistantSession() {
        assistantService.stop()
        assistantService.resetSessionID(for: assistantProvider)
        surfacedAssistantNotices.removeAll()
        assistantErrorBuffer = ""
        activeAssistantMessageID = nil
        assistantIsBusy = false
        assistantStatusMessage = nil
        appendAssistantSystemMessage("Assistant session restarted.")
    }

    private func appendAssistantNoticeOnce(_ notice: String) {
        if surfacedAssistantNotices.insert(notice).inserted {
            appendAssistantSystemMessage(notice)
        }
    }

    private func assistantChatWorkingDirectory() throws -> String {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(
                domain: "TermHub.Assistant",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Application Support directory is unavailable."]
            )
        }
        let chatDir = appSupport
            .appendingPathComponent("TermHub", isDirectory: true)
            .appendingPathComponent("AssistantChat", isDirectory: true)
        try fileManager.createDirectory(at: chatDir, withIntermediateDirectories: true)
        return chatDir.path
    }

    #if DEBUG
    func testAssistantChatWorkingDirectory() throws -> String {
        try assistantChatWorkingDirectory()
    }
    #endif

    func sendAssistantPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        assistantMessages.append(AssistantMessage(role: .user, content: trimmed))
        assistantInputText = ""
        assistantIsBusy = true
        assistantStatusMessage = "Running \(assistantProvider.displayName)…"
        assistantErrorBuffer = ""
        activeAssistantMessageID = nil
        scheduleSave()

        guard AssistantService.isCLIAvailable(for: assistantProvider) else {
            assistantIsBusy = false
            assistantStatusMessage = "Failed to send prompt."
            let message = AssistantService.AssistantServiceError.cliNotFound(assistantProvider).localizedDescription
                ?? "\(assistantProvider.displayName) CLI is not available."
            assistantMessages.append(AssistantMessage(role: .error, content: message))
            saveState()
            return
        }

        if mcpServerEnabled, !AssistantService.isMCPBinaryAvailable() {
            appendAssistantNoticeOnce("MCP server is enabled, but `termhub-mcp` was not found in the expected install locations.")
        }

        do {
            let assistantWorkingDirectory = try assistantChatWorkingDirectory()
            let notices = try assistantService.send(
                trimmed,
                provider: assistantProvider,
                mcpEnabled: mcpServerEnabled,
                allowedTools: assistantAllowedTools,
                model: assistantModel,
                effort: assistantModelSupportsEffort ? assistantEffort : "",
                workingDirectory: assistantWorkingDirectory
            )
            for notice in notices {
                appendAssistantNoticeOnce(notice)
            }
        } catch {
            assistantIsBusy = false
            assistantStatusMessage = "Failed to send prompt."
            assistantMessages.append(AssistantMessage(role: .error, content: error.localizedDescription))
            saveState()
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
        sandboxName: String? = nil
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
            sandboxName: sandboxName,
            folderName: folderName
        )

        if let sandboxName {
            lastUsedSandboxName = sandboxName
        }

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

    // MARK: - Sandbox Lifecycle

    func sandboxInfo(named name: String) -> SandboxInfo? {
        sandboxes.first { $0.name == name }
    }

    func refreshSandboxes() {
        Task.detached {
            let list = DockerSandboxService.listSandboxes()
            await MainActor.run { [weak self] in
                self?.sandboxes = list
            }
        }
    }

    func createSandbox(name: String, agent: SandboxAgent = .claude, workspacePath: String) {
        createSandbox(name: name, agent: agent, workspaces: [workspacePath])
    }

    func createSandbox(name: String, agent: SandboxAgent = .claude, workspaces: [String]) {
        sandboxOperationInProgress.insert(name)
        Task.detached {
            do {
                try DockerSandboxService.createSandbox(name: name, agent: agent.rawValue, workspaces: workspaces)
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

    func environmentKeysForSandbox(_ name: String) -> [String] {
        sandboxEnvironmentKeys[name] ?? []
    }

    func setSandboxEnvironmentKeys(_ keys: [String], for sandboxName: String) {
        if keys.isEmpty {
            sandboxEnvironmentKeys.removeValue(forKey: sandboxName)
        } else {
            sandboxEnvironmentKeys[sandboxName] = keys
        }
        saveState()
    }

    /// Resolves the configured environment variable names for a sandbox to their current host values.
    func resolvedEnvironmentVariables(for sandboxName: String) -> [String: String] {
        let keys = environmentKeysForSandbox(sandboxName)
        return DockerSandboxService.resolveEnvironmentVariables(keys: keys)
    }

    private func startSandboxPolling() {
        sandboxRefreshTimer?.invalidate()
        sandboxRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.sessions.contains(where: { $0.isSandboxSession }) else { return }
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
            let shellCommand: String? = if let sandboxName = session.sandboxName {
                DockerSandboxService.execCommand(
                    sandboxName: sandboxName,
                    cwd: cwd,
                    environmentVariables: resolvedEnvironmentVariables(for: sandboxName)
                )
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

    private func configureAssistantService() {
        assistantService.onOutput = { [weak self] chunk in
            Task { @MainActor [weak self] in
                self?.handleAssistantOutput(chunk)
            }
        }
        assistantService.onErrorOutput = { [weak self] chunk in
            Task { @MainActor [weak self] in
                self?.handleAssistantErrorOutput(chunk)
            }
        }
        assistantService.onExit = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.assistantIsBusy = false
                if status == 0 {
                    self?.assistantStatusMessage = nil
                } else {
                    if let provider = self?.assistantProvider {
                        self?.assistantStatusMessage = "\(provider.displayName) exited (\(status))."
                    }
                    let buffered = self?.assistantErrorBuffer.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !buffered.isEmpty {
                        self?.assistantMessages.append(AssistantMessage(role: .error, content: buffered))
                    }
                }
                self?.assistantErrorBuffer = ""
                self?.activeAssistantMessageID = nil
                self?.scheduleSave()
            }
        }
    }

    private func handleAssistantOutput(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        assistantIsBusy = true
        assistantStatusMessage = assistantRespondingText

        let messageID: UUID
        if let id = activeAssistantMessageID {
            messageID = id
        } else {
            let message = AssistantMessage(role: .assistant, content: "")
            assistantMessages.append(message)
            activeAssistantMessageID = message.id
            messageID = message.id
        }

        if let index = assistantMessages.firstIndex(where: { $0.id == messageID }) {
            assistantMessages[index].content += chunk
        }

        // Claude output is chunked; finalize after a brief idle window.
        assistantIdleWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.assistantIsBusy = false
                self?.assistantStatusMessage = nil
                self?.activeAssistantMessageID = nil
                self?.scheduleSave()
            }
        }
        assistantIdleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: workItem)
    }

    private func handleAssistantErrorOutput(_ chunk: String) {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if assistantErrorBuffer.isEmpty {
            assistantErrorBuffer = trimmed
        } else {
            assistantErrorBuffer += "\n\(trimmed)"
        }
        if let lastLine = trimmed.split(separator: "\n").last {
            assistantStatusMessage = String(lastLine)
        } else {
            assistantStatusMessage = trimmed
        }
        scheduleSave()
    }

    private func loadState() {
        isLoading = true
        defer { isLoading = false }
        do {
            let state = try persistence.load()
            folders = state.folders
            sessions = state.sessions
            for session in sessions {
                displayStates[session.id] = SessionDisplayState(title: session.title)
            }
            // Restore MRU order, falling back to sidebar order for sessions not in the persisted list.
            let validSessionIDs = Set(sessions.map(\.id))
            let persisted = (state.sessionMRUOrder ?? []).filter { validSessionIDs.contains($0) }
            let missing = allSessionIDsOrdered.filter { !persisted.contains($0) }
            sessionMRUOrder = persisted + missing
            selectedSessionID = state.selectedSessionID
            sandboxEnvironmentKeys = state.sandboxEnvironmentKeys ?? [:]
            assistantMessages = state.assistantMessages ?? []
            let persistedAllowedToolsByProvider = state.assistantAllowedToolsByProvider ?? [:]
            if !persistedAllowedToolsByProvider.isEmpty {
                assistantAllowedToolsByProvider = Self.normalizedAssistantAllowedToolsByProvider(persistedAllowedToolsByProvider)
            }
            let sessionIDsByProvider = state.assistantSessionIdsByProvider ?? [:]
            if sessionIDsByProvider.isEmpty, let legacyClaudeSessionID = state.assistantSessionId {
                assistantService.setSessionIDs([AssistantProvider.claude.rawValue: legacyClaudeSessionID])
            } else {
                assistantService.setSessionIDs(sessionIDsByProvider)
            }
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
            sessionMRUOrder: sessionMRUOrder,
            sandboxEnvironmentKeys: sandboxEnvironmentKeys.isEmpty ? nil : sandboxEnvironmentKeys,
            assistantMessages: assistantMessages.isEmpty ? nil : assistantMessages,
            assistantSessionId: assistantService.sessionID(for: .claude),
            assistantSessionIdsByProvider: assistantService.sessionIDs(),
            assistantAllowedToolsByProvider: assistantAllowedToolsByProvider
        )
        let persistence = self.persistence
        persistence.scheduleWrite {
            do {
                try persistence.save(state: state)
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

    /// Returns true if the current keyboard layout is US-style (where Option
    /// is not needed for common characters like @, {, }, etc.).
    private static func detectUSKeyboardLayout() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
              let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String?
        else {
            return true
        }
        // US, ABC, and British layouts don't use Option for basic characters
        let usStyleLayouts = ["US", "ABC", "British", "Australian", "Canadian", "USInternational"]
        return usStyleLayouts.contains { id.contains($0) }
    }
}

final class AssistantService: @unchecked Sendable {
    private struct ProviderCapabilities {
        let supportsSystemPrompt: Bool
        let supportsWildcardAllowedTools: Bool
    }

    var onOutput: (@Sendable (String) -> Void)?
    var onErrorOutput: (@Sendable (String) -> Void)?
    var onExit: (@Sendable (Int32) -> Void)?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var sessionIDsByProvider: [String: UUID] = [:]
    nonisolated(unsafe) static var commandExistsOverride: ((String) -> Bool)?

    private static let baseSystemPrompt = """
        You are the TermHub Assistant, a helpful AI built into TermHub — a native macOS app for \
        managing terminal sessions across multiple project folders with tmux-backed persistence \
        and git worktree integration.

        Key concepts in TermHub:
        - **Folders**: Project directories the user has added to TermHub for management.
        - **Sessions**: Terminal tabs within a folder. Each session is backed by a tmux session \
          for persistence. Sessions can optionally be associated with a git worktree and branch.
        - **Worktrees**: Git worktree sessions let users work on multiple branches of the same \
          repo simultaneously, each in its own terminal session.
        - **Sandboxes**: Docker-based isolated environments that sessions can run inside.

        You can answer questions about the user's workspace, help them manage sessions and \
        folders, explain git worktree workflows, and assist with terminal tasks. Be concise \
        and helpful.
        """

    private static let mcpSystemPromptAddendum = """

        You have access to the TermHub MCP server, which lets you directly interact with the \
        user's workspace. Use it to answer questions about their folders, sessions, worktrees, \
        and sandboxes. For example, call get_workspace_overview to see everything at a glance, \
        list_sessions to check active sessions, send_keys to run commands in a terminal, or \
        create_worktree to set up a new branch workspace. Always prefer using the MCP tools \
        over asking the user to do things manually.
        """

    private static let mcpBinaryPath: String? = {
        // Prefer ~/.local/bin path since the MCP config "command" field
        // doesn't handle spaces in paths (Application Support has a space).
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localBin = home.appendingPathComponent(".local/bin/termhub-mcp").path
        if FileManager.default.fileExists(atPath: localBin) {
            return localBin
        }
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appSupportBin = appSupport.appendingPathComponent("TermHub/termhub-mcp").path
        if FileManager.default.fileExists(atPath: appSupportBin) {
            return appSupportBin
        }
        return nil
    }()

    enum AssistantServiceError: Error, LocalizedError {
        case cliNotFound(AssistantProvider)

        var errorDescription: String? {
            switch self {
            case .cliNotFound(let provider):
                return "\(provider.displayName) CLI is not available. Install it and make sure it is in PATH."
            }
        }
    }

    static func isCLIAvailable(for provider: AssistantProvider) -> Bool {
        switch provider {
        case .claude:
            return commandExists("claude")
        case .copilot:
            return commandExists("copilot")
        }
    }

    static func isMCPBinaryAvailable() -> Bool {
        mcpBinaryPath != nil
    }

    func sessionID(for provider: AssistantProvider) -> UUID? {
        sessionIDsByProvider[provider.rawValue]
    }

    func setSessionIDs(_ sessionIDs: [String: UUID]) {
        sessionIDsByProvider = sessionIDs
    }

    func sessionIDs() -> [String: UUID] {
        sessionIDsByProvider
    }

    func resetSessionID(for provider: AssistantProvider) {
        sessionIDsByProvider.removeValue(forKey: provider.rawValue)
    }

    func resetAllSessionIDs() {
        sessionIDsByProvider.removeAll()
    }

    /// Sends a prompt to the configured provider in non-interactive mode.
    /// Returns system notices for best-effort capability differences.
    func send(
        _ text: String,
        provider: AssistantProvider,
        mcpEnabled: Bool,
        allowedTools: String = "",
        model: String = "",
        effort: String = "",
        workingDirectory: String?
    ) throws -> [String] {
        // If a previous process is still running, terminate it first.
        if process?.isRunning == true {
            process?.terminate()
            process?.waitUntilExit()
        }
        cleanupPipes()

        switch provider {
        case .claude:
            guard Self.commandExists("claude") else {
                throw AssistantServiceError.cliNotFound(.claude)
            }
        case .copilot:
            guard Self.commandExists("copilot") else {
                throw AssistantServiceError.cliNotFound(.copilot)
            }
        }

        let isFirstMessage = sessionIDsByProvider[provider.rawValue] == nil
        let sessionID: UUID
        if let existing = sessionIDsByProvider[provider.rawValue] {
            sessionID = existing
        } else {
            sessionID = UUID()
            sessionIDsByProvider[provider.rawValue] = sessionID
        }

        let build = Self.buildArguments(
            text: text,
            provider: provider,
            mcpEnabled: mcpEnabled,
            allowedTools: allowedTools,
            model: model,
            effort: effort,
            isFirstMessage: isFirstMessage,
            sessionID: sessionID
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = build.args

        let notices = build.notices

        if let workingDirectory,
           !workingDirectory.isEmpty,
           FileManager.default.fileExists(atPath: workingDirectory)
        {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        } else {
            process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        }

        let stdout = Pipe()
        let stderr = Pipe()

        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.onOutput?(text)
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.onErrorOutput?(text)
        }

        process.terminationHandler = { [weak self] proc in
            self?.cleanupPipes()
            self?.onExit?(proc.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        self.process = process
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        return notices
    }

    func stop() {
        cleanupPipes()
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
    }

    private func cleanupPipes() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private static func commandExists(_ command: String) -> Bool {
        if let override = commandExistsOverride {
            return override(command)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func capabilities(for provider: AssistantProvider) -> ProviderCapabilities {
        switch provider {
        case .claude:
            return ProviderCapabilities(
                supportsSystemPrompt: true,
                supportsWildcardAllowedTools: true
            )
        case .copilot:
            return ProviderCapabilities(
                supportsSystemPrompt: false,
                supportsWildcardAllowedTools: false
            )
        }
    }

    private static func parsedToolsList(_ allowedTools: String) -> [String] {
        allowedTools
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func sanitizeToolsList(_ tools: [String], for provider: AssistantProvider) -> (safe: [String], ignored: [String]) {
        let capabilities = capabilities(for: provider)
        guard !capabilities.supportsWildcardAllowedTools else {
            return (safe: tools, ignored: [])
        }

        var safe: [String] = []
        var ignored: [String] = []
        for tool in tools {
            if tool.contains("*") || tool.contains("?") {
                ignored.append(tool)
            } else {
                safe.append(tool)
            }
        }
        return (safe: safe, ignored: ignored)
    }

    private static func buildArguments(
        text: String,
        provider: AssistantProvider,
        mcpEnabled: Bool,
        allowedTools: String,
        model: String,
        effort: String,
        isFirstMessage: Bool,
        sessionID: UUID
    ) -> (args: [String], notices: [String]) {
        var notices: [String] = []
        var args: [String] = []
        let toolsList = parsedToolsList(allowedTools)
        let sanitizedTools = sanitizeToolsList(toolsList, for: provider)
        let safeToolsList = sanitizedTools.safe
        let ignoredToolsList = sanitizedTools.ignored
        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEffort = effort.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .claude:
            args = ["claude", "-p"]
            if !resolvedModel.isEmpty { args += ["--model", resolvedModel] }
            if !resolvedEffort.isEmpty { args += ["--effort", resolvedEffort] }
            if isFirstMessage {
                args += ["--session-id", sessionID.uuidString]
                var systemPrompt = Self.baseSystemPrompt
                if mcpEnabled {
                    systemPrompt += Self.mcpSystemPromptAddendum
                }
                if capabilities(for: .claude).supportsSystemPrompt {
                    args += ["--system-prompt", systemPrompt]
                }
            } else {
                args += ["--resume", sessionID.uuidString]
            }
            if mcpEnabled, let mcpBinary = Self.mcpBinaryPath {
                let mcpConfig = """
                    {"mcpServers":{"termhub":{"type":"stdio","command":"\(mcpBinary)","args":[]}}}
                    """
                args += ["--mcp-config", mcpConfig]
            } else if mcpEnabled {
                notices.append("MCP server is enabled, but `termhub-mcp` was not found in the expected install locations.")
            }
            if !safeToolsList.isEmpty {
                args += ["--allowedTools"] + safeToolsList
            }
            // Use "--" to separate options from the prompt, since --mcp-config is
            // variadic and would otherwise consume the prompt as a config argument.
            args += ["--", text]

        case .copilot:
            args = ["copilot", "-p", text]
            if !resolvedModel.isEmpty { args += ["--model", resolvedModel] }
            if !resolvedEffort.isEmpty { args += ["--reasoning-effort", resolvedEffort] }
            args += [
                "--output-format", "text",
                "--stream", "off",
                "-s",
                "--allow-all-tools",
            ]
            if !isFirstMessage {
                args += ["--resume", sessionID.uuidString]
            }
            if mcpEnabled, let mcpBinary = Self.mcpBinaryPath {
                let mcpConfig = """
                    {"mcpServers":{"termhub":{"type":"stdio","command":"\(mcpBinary)","args":[]}}}
                    """
                args += ["--additional-mcp-config", mcpConfig]
            } else if mcpEnabled {
                notices.append("MCP server is enabled, but `termhub-mcp` was not found in the expected install locations.")
            }
            if !safeToolsList.isEmpty {
                for tool in safeToolsList {
                    args += ["--allow-tool", tool]
                }
            }
            if !ignoredToolsList.isEmpty {
                let ignored = ignoredToolsList.joined(separator: ", ")
                notices.append(
                    "Ignored unsupported Copilot Allowed Tools pattern(s): \(ignored). "
                        + "Use concrete tool names only (no wildcards)."
                )
            }
        }
        return (args, notices)
    }

    #if DEBUG
    func testBuildArguments(
        text: String,
        provider: AssistantProvider,
        mcpEnabled: Bool,
        allowedTools: String,
        model: String = "",
        effort: String = "",
        isFirstMessage: Bool,
        sessionID: UUID
    ) -> (args: [String], notices: [String]) {
        Self.buildArguments(
            text: text,
            provider: provider,
            mcpEnabled: mcpEnabled,
            allowedTools: allowedTools,
            model: model,
            effort: effort,
            isFirstMessage: isFirstMessage,
            sessionID: sessionID
        )
    }
    #endif
}
