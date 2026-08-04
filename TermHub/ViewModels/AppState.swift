import AppKit
import Carbon
import Foundation
import Observation

enum AssistantProvider: String, CaseIterable, Codable, Sendable {
    case claude
    case copilot
    case codex

    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .copilot:
            return "GitHub Copilot"
        case .codex:
            return "OpenAI Codex"
        }
    }

    var commandName: String { rawValue }
}

struct WorktreeDiscoveryService: Sendable {
    var listWorktrees: @Sendable (_ repoPath: String, _ folderID: UUID) throws -> [GitWorktree]
    var liveTmuxSessionNames: @Sendable () -> Set<String>

    static let live = WorktreeDiscoveryService(
        listWorktrees: { repoPath, folderID in
            try GitService.listWorktrees(repoPath: repoPath, folderID: folderID)
        },
        liveTmuxSessionNames: {
            Set(TmuxService.listSessions())
        }
    )
}

@Observable
@MainActor
final class AppState {
    private static let assistantAllowedToolsByProviderUserDefaultsKey = "assistantAllowedToolsByProvider"
    private static let legacyAssistantAllowedToolsUserDefaultsKey = "assistantAllowedTools"
    private static let assistantModelByProviderUserDefaultsKey = "assistantModelByProvider"
    private static let assistantEffortByProviderUserDefaultsKey = "assistantEffortByProvider"
    private static let assistantCLIPathsUserDefaultsKey = "assistantCLIPaths"
    private static let revealSelectedSessionInSidebarOnCtrlTabUserDefaultsKey = "revealSelectedSessionInSidebarOnCtrlTab"

    private static func defaultAssistantAllowedTools(for provider: AssistantProvider) -> String {
        switch provider {
        case .claude:
            return "WebFetch,mcp__termhub__*"
        case .copilot:
            return "WebFetch"
        case .codex:
            return ""
        }
    }

    static func defaultAssistantModel(for provider: AssistantProvider) -> String {
        switch provider {
        case .claude: return "default"
        case .copilot: return "claude-haiku-4.5"
        case .codex: return "gpt-5.6-luna"
        }
    }

    static func assistantModelDisplayName(for provider: AssistantProvider, model: String) -> String {
        switch provider {
        case .claude:
            switch model {
            case "default": return "Default (recommended) · Opus 4.6 · 1M context"
            case "sonnet": return "Sonnet · Sonnet 4.6"
            case "sonnet-1m": return "Sonnet (1M context) · Sonnet 4.6"
            case "haiku": return "Haiku · Haiku 4.5"
            default: return model
            }
        case .copilot:
            return model
        case .codex:
            switch model {
            case "gpt-5.6-terra": return "GPT-5.6 Terra"
            case "gpt-5.6-luna": return "GPT-5.6 Luna"
            default: return model
            }
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
        case .codex:
            return ["gpt-5.6-terra", "gpt-5.6-luna"]
        }
    }

    static func defaultAssistantEffort(for provider: AssistantProvider) -> String {
        switch provider {
        case .claude: return "low"
        case .copilot: return ""
        case .codex: return "medium"
    }
}

    static func assistantEffortOptions(for provider: AssistantProvider, model: String? = nil) -> [String] {
        switch provider {
        case .claude, .copilot:
            return ["", "low", "medium", "high", "xhigh"]
        case .codex:
            switch model {
            case "gpt-5.6-terra":
                return ["", "low", "medium", "high", "xhigh", "max", "ultra"]
            case "gpt-5.6-luna":
                return ["", "low", "medium", "high", "xhigh", "max"]
            default:
                // The provider-level list is also used when normalizing persisted
                // values before the selected model is available.
                return ["", "low", "medium", "high", "xhigh", "max", "ultra"]
            }
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
        case .codex:
            return assistantModelOptions(for: .codex).contains(model)
        }
    }

    private static func normalizedAssistantModel(_ value: String, for provider: AssistantProvider) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard assistantModelOptions(for: provider).contains(trimmed) else {
            return defaultAssistantModel(for: provider)
        }
        return trimmed
    }

    private static func normalizedAssistantEffort(
        _ value: String,
        for provider: AssistantProvider,
        model: String? = nil
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard assistantEffortOptions(for: provider, model: model).contains(trimmed) else {
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
    var groups: [FolderGroup] = []
    var sidebarOrder: [SidebarItem] = []
    @ObservationIgnored var sessions: [TerminalSession] = []
    @ObservationIgnored private var displayStates: [UUID: SessionDisplayState] = [:]

    func displayState(for id: UUID) -> SessionDisplayState? {
        displayStates[id]
    }
    var selectedSessionID: UUID? {
        didSet {
            if oldValue != selectedSessionID, !isSelectingInputSessionFromTraversal {
                resetInputSessionTraversal()
            }
            if let id = selectedSessionID, NSApp?.isActive == true {
                sessionsNeedingAttention.remove(id)
            }
            if let id = selectedSessionID, !isSessionSwitcherActive {
                updateMRUOrder(selectedID: id)
            }
            if !isLoading, selectedSessionID != nil {
                saveState()
            }
            if !isLoading, oldValue != selectedSessionID {
                refreshSelectedSessionPullRequest()
            }
        }
    }
    private(set) var sidebarRevealSessionID: UUID?
    private(set) var sessionMRUOrder: [UUID] = []
    private(set) var sessionInputMRUOrder: [UUID] = []
    @ObservationIgnored private(set) var sessionLastInputAt: [UUID: Date] = [:]
    @ObservationIgnored private var inputSessionTraversal: [UUID] = []
    @ObservationIgnored private var inputSessionTraversalIndex: Int?
    @ObservationIgnored private var isSelectingInputSessionFromTraversal = false
    var isSessionSwitcherActive = false
    var switcherSelectedIndex: Int = 0
    private(set) var sessionSwitcherReferenceDate = Date()
    var revealSelectedSessionInSidebarOnCtrlTab: Bool {
        didSet {
            UserDefaults.standard.set(
                revealSelectedSessionInSidebarOnCtrlTab,
                forKey: Self.revealSelectedSessionInSidebarOnCtrlTabUserDefaultsKey
            )
        }
    }
    var tmuxAvailable: Bool = false
    var pendingWorktreeFolder: ManagedFolder?
    var pendingNewBranchFolder: ManagedFolder?
    var pendingCheckoutBranchFolder: ManagedFolder?
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
    private(set) var selectedSessionPullRequestURL: URL?
    private(set) var isSelectedSessionPullRequestLoading = false
    private(set) var worktreesByFolderID: [UUID: [GitWorktree]] = [:]
    private(set) var worktreeDiscoveryErrors: [UUID: String] = [:]
    private(set) var worktreeDiscoveryInProgress: Set<UUID> = []
    private(set) var worktreeRemovalInProgress: Set<String> = []
    var detailTabBySession: [UUID: DetailTab] = [:]
    var showSandboxManager = false
    var sandboxes: [SandboxInfo] = []
    var sandboxOperationInProgress: Set<String> = []
    /// Per-sandbox environment variable names to forward from the host into sandbox shells.
    var sandboxEnvironmentKeys: [String: [String]] = [:]
    /// Debounce work items for sandbox terminal resize stty commands.
    @ObservationIgnored private var sandboxResizeDebounce: [UUID: DispatchWorkItem] = [:]
    private var sandboxRefreshTimer: Timer?
    private var sandboxRefreshInProgress = false
    var currentDiff: GitDiff?
    var isDiffLoading = false
    @ObservationIgnored private let gitFileWatcher = GitFileWatcher()
    @ObservationIgnored private var gitWatchPathsByTrackedPath: [String: [String]] = [:]
    @ObservationIgnored private var gitStatusRefreshSequence: UInt64 = 0
    @ObservationIgnored private var latestGitStatusRefreshByPath: [String: UInt64] = [:]
    @ObservationIgnored private var worktreeRefreshGenerationByFolderID: [UUID: UInt64] = [:]
    @ObservationIgnored private var foldersWithSuccessfulWorktreeDiscovery: Set<UUID> = []
    @ObservationIgnored private var worktreeRefreshDebounce: DispatchWorkItem?
    @ObservationIgnored private var worktreeTrackingReconciliationNeeded = false
    @ObservationIgnored private var pendingWorktreeStatusRefreshPaths: Set<String> = []
    private var lastBellTime: [UUID: Date] = [:]
    private var isLoading = false
    private var loadFailed = false
    @ObservationIgnored private var debouncedSaveWorkItem: DispatchWorkItem?
    @ObservationIgnored private let persistence: StatePersistence
    @ObservationIgnored private let worktreeDiscoveryService: WorktreeDiscoveryService
    @ObservationIgnored private let pullRequestLookupService: PullRequestLookupService
    @ObservationIgnored private var pullRequestRefreshSequence: UInt64 = 0
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

    var sendTTYSizeToSandboxTerminals: Bool {
        didSet {
            UserDefaults.standard.set(sendTTYSizeToSandboxTerminals, forKey: "sendTTYSizeToSandboxTerminals")
            terminalManager.sendTTYSizeToSandboxTerminals = sendTTYSizeToSandboxTerminals
            if !sendTTYSizeToSandboxTerminals {
                sandboxResizeDebounce.values.forEach { $0.cancel() }
                sandboxResizeDebounce.removeAll()
            }
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

    /// Paths are stored per provider so switching providers does not lose a custom override.
    var assistantCLIPaths: [String: String] {
        didSet {
            UserDefaults.standard.set(assistantCLIPaths, forKey: Self.assistantCLIPathsUserDefaultsKey)
        }
    }

    var assistantCLIPath: String {
        get { assistantCLIPaths[assistantProvider.rawValue] ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let expanded = (trimmed as NSString).expandingTildeInPath
            if expanded.isEmpty {
                assistantCLIPaths.removeValue(forKey: assistantProvider.rawValue)
            } else {
                assistantCLIPaths[assistantProvider.rawValue] = expanded
            }
        }
    }

    var assistantCLIPathIsAvailable: Bool {
        guard !assistantCLIPath.isEmpty else { return false }
        return AssistantService.isCLIAvailable(for: assistantProvider, executablePath: assistantCLIPath)
    }

    func detectAssistantCLIPath() {
        if let detectedPath = AssistantService.detectCLIPath(for: assistantProvider) {
            assistantCLIPath = detectedPath
        }
    }

    var assistantEffort: String {
        get {
            let value = assistantEffortByProvider[assistantProvider.rawValue]
                ?? Self.defaultAssistantEffort(for: assistantProvider)
            return Self.normalizedAssistantEffort(value, for: assistantProvider, model: assistantModel)
        }
        set {
            assistantEffortByProvider[assistantProvider.rawValue] = Self.normalizedAssistantEffort(
                newValue,
                for: assistantProvider,
                model: assistantModel
            )
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
        case .codex:
            return "Not used by Codex"
        }
    }

    var assistantAllowedToolsHelpText: String {
        switch assistantProvider {
        case .claude:
            return "Claude-only setting. Comma-separated tools for Claude `--allowedTools`."
        case .copilot:
            return "Copilot-only setting. Use concrete tool names only (no wildcards like `*`)."
        case .codex:
            return "Codex does not currently accept TermHub Allowed Tools or one-shot MCP injection, so this setting is ignored."
        }
    }

    var assistantEmptyStateText: String {
        switch assistantProvider {
        case .claude:
            return "Ask anything. Claude can use the TermHub MCP server to manage sessions, worktrees, and sandboxes."
        case .copilot:
            return "Ask anything. Copilot can use the TermHub MCP server when enabled. If responses fail, verify Copilot Allowed Tools use concrete names (no wildcards)."
        case .codex:
            return "Ask anything. Codex runs through `codex exec`. In TermHub this currently behaves as one-shot prompts rather than a resumable conversation."
        }
    }

    let terminalManager = TerminalSessionManager()

    init(
        persistence: StatePersistence? = nil,
        worktreeDiscoveryService: WorktreeDiscoveryService = .live,
        pullRequestLookupService: PullRequestLookupService? = nil
    ) {
        let isTestHost = ProcessInfo.processInfo.isRunningTests
        self.persistence = persistence ?? (isTestHost ? NullPersistence() : DiskPersistence())
        self.worktreeDiscoveryService = worktreeDiscoveryService
        self.pullRequestLookupService = pullRequestLookupService
            ?? (isTestHost ? .unavailable : .live)
        if UserDefaults.standard.bool(forKey: "optionAsMetaKeyIsSet") {
            optionAsMetaKey = UserDefaults.standard.bool(forKey: "optionAsMetaKey")
        } else {
            optionAsMetaKey = Self.detectUSKeyboardLayout()
        }
        copyClaudeSettingsToWorktrees = UserDefaults.standard.object(forKey: "copyClaudeSettingsToWorktrees") as? Bool ?? true
        sendTTYSizeToSandboxTerminals = UserDefaults.standard.object(forKey: "sendTTYSizeToSandboxTerminals") as? Bool ?? true
        revealSelectedSessionInSidebarOnCtrlTab = UserDefaults.standard.object(
            forKey: Self.revealSelectedSessionInSidebarOnCtrlTabUserDefaultsKey
        ) as? Bool ?? true
        assistantProvider = AssistantProvider(rawValue: UserDefaults.standard.string(forKey: "assistantProvider") ?? "") ?? .claude
        assistantAllowedToolsByProvider = Self.loadAssistantAllowedToolsByProviderFromUserDefaults()
        assistantModelByProvider = Self.normalizedAssistantModelByProvider(
            UserDefaults.standard.dictionary(forKey: Self.assistantModelByProviderUserDefaultsKey) as? [String: String] ?? [:]
        )
        assistantEffortByProvider = Self.normalizedAssistantEffortByProvider(
            UserDefaults.standard.dictionary(forKey: Self.assistantEffortByProviderUserDefaultsKey) as? [String: String] ?? [:]
        )
        var storedCLIPaths = UserDefaults.standard.dictionary(forKey: Self.assistantCLIPathsUserDefaultsKey) as? [String: String] ?? [:]
        for provider in AssistantProvider.allCases where storedCLIPaths[provider.rawValue] == nil {
            if let detectedPath = AssistantService.detectCLIPath(for: provider) {
                storedCLIPaths[provider.rawValue] = detectedPath
            }
        }
        assistantCLIPaths = storedCLIPaths
        mcpServerEnabled = UserDefaults.standard.object(forKey: "mcpServerEnabled") as? Bool ?? true
        terminalManager.optionAsMetaKey = optionAsMetaKey
        terminalManager.sendTTYSizeToSandboxTerminals = sendTTYSizeToSandboxTerminals
        tmuxAvailable = isTestHost ? false : TmuxService.isAvailable()
        loadState()
        configureAssistantService()
        if !isTestHost {
            detectGitRepos()
            refreshWorktrees()
            restoreTmuxSessions()
        }

        terminalManager.onBell = { [weak self] sessionID in
            self?.markNeedsAttention(sessionID: sessionID)
        }

        terminalManager.onKeyboardInput = { [weak self] sessionID in
            self?.recordSessionKeyboardInput(sessionID: sessionID)
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
                self?.refreshWorktrees()
                self?.refreshSelectedSessionPullRequest()
            }
        }

        terminalManager.onTitleChange = { [weak self] sessionID, title in
            self?.handleTerminalTitleChange(sessionID: sessionID, title: title)
        }

        terminalManager.onResize = { [weak self] sessionID, cols, rows in
            self?.handleTerminalResize(sessionID: sessionID, cols: cols, rows: rows)
        }

        if !isTestHost {
            refreshGitStatuses()
            updateGitFileWatcher()
            refreshSelectedSessionPullRequest()
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

    var selectedFolder: ManagedFolder? {
        guard let selectedSession else { return nil }
        return folders.first { $0.id == selectedSession.folderID }
    }

    func selectSession(id: UUID, revealInSidebar: Bool = false) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        selectedSessionID = id
        if revealInSidebar {
            revealSessionInSidebar(id)
        }
    }

    func requestSidebarReveal(for sessionID: UUID) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        sidebarRevealSessionID = sessionID
    }

    func clearSidebarRevealRequest() {
        sidebarRevealSessionID = nil
    }

    private func revealSessionInSidebar(_ sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID }),
              let folderIndex = folders.firstIndex(where: { $0.id == session.folderID })
        else {
            requestSidebarReveal(for: sessionID)
            return
        }

        if let groupID = group(forFolderID: session.folderID)?.id,
           let group = groups.first(where: { $0.id == groupID }),
           !group.isExpanded
        {
            setGroupExpanded(id: groupID, isExpanded: true)
        }

        if !folders[folderIndex].isExpanded {
            setFolderExpanded(id: session.folderID, isExpanded: true)
        }

        requestSidebarReveal(for: sessionID)
    }

    /// All sessions ordered by folder for keyboard navigation (matches sidebar visual order).
    var allSessionIDsOrdered: [UUID] {
        var result: [UUID] = []
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let folderByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let groupByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

        func appendSessions(for folder: ManagedFolder) {
            guard folder.isExpanded else { return }
            let validIDs = folder.sessionIDs.filter { sessionByID[$0] != nil }
            let plain = validIDs.filter { id in
                sessionByID[id]?.worktreePath == nil
            }
            var seenWorktrees: [String: [UUID]] = [:]
            var worktreeOrder: [String] = []
            for id in validIDs {
                guard let session = sessionByID[id],
                      let wt = session.worktreePath else { continue }
                if seenWorktrees[wt] == nil {
                    worktreeOrder.append(wt)
                }
                seenWorktrees[wt, default: []].append(id)
            }
            let worktree = worktreeOrder.flatMap { seenWorktrees[$0] ?? [] }
            result.append(contentsOf: plain + worktree)
        }

        for item in sidebarOrder {
            switch item {
            case .folder(let folderID):
                if let folder = folderByID[folderID] {
                    appendSessions(for: folder)
                }
            case .group(let groupID):
                guard let group = groupByID[groupID],
                      group.isExpanded else { continue }
                for folderID in group.folderIDs {
                    if let folder = folderByID[folderID] {
                        appendSessions(for: folder)
                    }
                }
            }
        }

        return result
    }

    func toggleAssistant() {
        if showAssistant {
            showAssistant = false
            return
        }

        guard selectedFolder != nil else { return }
        showAssistant = true
    }

    func appendAssistantSystemMessage(_ content: String) {
        assistantMessages.append(AssistantMessage(role: .system, content: content))
        scheduleSave()
    }

    func clearAssistantChat() {
        assistantIdleWorkItem?.cancel()
        assistantIdleWorkItem = nil
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
        assistantIdleWorkItem?.cancel()
        assistantIdleWorkItem = nil
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

        guard AssistantService.isCLIAvailable(for: assistantProvider, executablePath: assistantCLIPath) else {
            assistantIsBusy = false
            assistantStatusMessage = "Failed to send prompt."
            let message = AssistantService.AssistantServiceError.cliNotFound(assistantProvider).localizedDescription
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
                workingDirectory: assistantWorkingDirectory,
                executablePath: assistantCLIPath
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
        sidebarOrder.append(.folder(folder.id))

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
        if folder.isGitRepo {
            // ManagedFolder detects existing Git repositories during initialization;
            // hydrate the status now that the folder is tracked by AppState.
            refreshGitStatuses(for: [path])
            refreshWorktrees(folderIDs: [folder.id])
        } else {
            // Detect repositories that were not identified during initialization
            // asynchronously so the UI remains responsive.
            detectGitRepos()
        }

        if selectedSessionID == nil {
            selectedSessionID = session.id
        }
    }

    func removeFolder(id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let folder = folders[index]

        AssistantPanel.removeAssistant(for: id)

        // Remove all sessions belonging to this folder (with cleanup)
        for sessionID in folder.sessionIDs {
            removeSession(id: sessionID, save: false)
        }

        folders.remove(at: index)
        worktreesByFolderID.removeValue(forKey: id)
        worktreeDiscoveryErrors.removeValue(forKey: id)
        worktreeDiscoveryInProgress.remove(id)
        foldersWithSuccessfulWorktreeDiscovery.remove(id)
        worktreeRefreshGenerationByFolderID.removeValue(forKey: id)
        sidebarOrder.removeAll { $0 == .folder(id) }
        // Also remove from any group it belongs to
        for i in groups.indices where groups[i].folderIDs.contains(id) {
            groups[i].folderIDs.removeAll { $0 == id }
        }
        saveState()
        updateGitFileWatcher()
    }

    func setFolderExpanded(id: UUID, isExpanded: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].isExpanded = isExpanded
        saveState()
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
        if let worktreePath {
            updateGitFileWatcher()
            refreshGitStatuses(for: [worktreePath])
            refreshWorktrees(folderIDs: [folderID])
        }
    }

    func removeSession(id: UUID, save: Bool = true) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        let tmuxName = session.tmuxSessionName
        removeSessionRecord(id: id, save: save)

        Task.detached {
            do { try TmuxService.killSession(name: tmuxName) }
            catch { print("[TermHub] Failed to kill tmux session '\(tmuxName)': \(error)") }
        }
    }

    private func removeSessionRecord(
        id: UUID,
        save: Bool,
        updateGitTracking: Bool = true
    ) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        if selectedSessionID == id {
            selectedSessionID = nextSessionID(after: id, inFolderOf: session)
        }

        terminalManager.destroyTerminal(for: id)
        sessionsNeedingAttention.remove(id)
        sandboxResizeDebounce[id]?.cancel()
        sandboxResizeDebounce.removeValue(forKey: id)
        lastBellTime.removeValue(forKey: id)
        displayStates.removeValue(forKey: id)
        detailTabBySession.removeValue(forKey: id)
        sessionMRUOrder.removeAll { $0 == id }
        sessionInputMRUOrder.removeAll { $0 == id }
        sessionLastInputAt.removeValue(forKey: id)
        sessions.removeAll { $0.id == id }

        for i in folders.indices {
            folders[i].sessionIDs.removeAll { $0 == id }
        }

        sessionListVersion += 1
        if save { saveState() }
        if updateGitTracking, session.worktreePath != nil {
            updateGitFileWatcher()
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

    /// Propagates terminal dimensions to sandbox sessions via stty.
    /// sbx exec does not forward SIGWINCH, so we must explicitly set the
    /// terminal size inside the container on every resize.
    /// Debounced to avoid flooding stty commands during drag-resize.
    private func handleTerminalResize(sessionID: UUID, cols: Int, rows: Int) {
        guard sendTTYSizeToSandboxTerminals else { return }
        guard let session = sessions.first(where: { $0.id == sessionID }),
              session.isSandboxSession
        else { return }

        sandboxResizeDebounce[sessionID]?.cancel()

        let workItem = Self.makeSandboxResizeWorkItem(
            sessionName: session.tmuxSessionName,
            cols: cols,
            rows: rows
        )
        sandboxResizeDebounce[sessionID] = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    nonisolated private static func makeSandboxResizeWorkItem(
        sessionName: String,
        cols: Int,
        rows: Int
    ) -> DispatchWorkItem {
        DispatchWorkItem {
            sendSandboxResize(sessionName: sessionName, cols: cols, rows: rows)
        }
    }

    nonisolated private static func sendSandboxResize(sessionName: String, cols: Int, rows: Int) {
        try? TmuxService.sendKeys(
            sessionName: sessionName,
            text: "stty rows \(rows) cols \(cols)"
        )
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

    /// Sandboxes that mount the directory where a new session will start.
    func sandboxes(applicableTo directory: String) -> [SandboxInfo] {
        sandboxes.filter { $0.applies(to: directory) }
    }

    func refreshSandboxes() {
        guard !sandboxRefreshInProgress else { return }
        sandboxRefreshInProgress = true
        Task.detached {
            let list = SbxService.listSandboxes()
            await MainActor.run { [weak self] in
                self?.sandboxes = list
                self?.sandboxRefreshInProgress = false
            }
        }
    }

    func createSandbox(name: String, agent: SandboxAgent = .claude, workspacePath: String, kitPath: String? = nil) {
        createSandbox(name: name, agent: agent, workspaces: [workspacePath], kitPath: kitPath)
    }

    func createSandbox(name: String, agent: SandboxAgent = .claude, workspaces: [String], kitPath: String? = nil) {
        sandboxOperationInProgress.insert(name)
        Task.detached {
            do {
                try SbxService.createSandbox(name: name, agent: agent.rawValue, workspaces: workspaces, kitPath: kitPath)
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Failed to create sandbox: \(msg)"
                }
            }
            let list = SbxService.listSandboxes()
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
                try SbxService.stopSandbox(name: name)
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Failed to stop sandbox: \(msg)"
                }
            }
            let list = SbxService.listSandboxes()
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
                try SbxService.removeSandbox(name: name)
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Failed to remove sandbox: \(msg)"
                }
            }
            let list = SbxService.listSandboxes()
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
        return SbxService.resolveEnvironmentVariables(keys: keys)
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

    func moveFolder(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              folders.indices.contains(sourceIndex),
              folders.indices.contains(destinationIndex) else { return }
        let folder = folders.remove(at: sourceIndex)
        folders.insert(folder, at: destinationIndex)
        saveState()
    }

    // MARK: - Group Management

    func addGroup(name: String) {
        let group = FolderGroup(name: name)
        groups.append(group)
        sidebarOrder.append(.group(group.id))
        saveState()
    }

    func removeGroup(id: UUID) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == id }) else { return }
        let group = groups[groupIndex]

        // Move contained folders back to ungrouped, inserted where the group was
        if let sidebarIndex = sidebarOrder.firstIndex(of: .group(id)) {
            sidebarOrder.remove(at: sidebarIndex)
            let folderItems = group.folderIDs.map { SidebarItem.folder($0) }
            sidebarOrder.insert(contentsOf: folderItems, at: sidebarIndex)
        }

        groups.remove(at: groupIndex)
        saveState()
    }

    func renameGroup(id: UUID, name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
        saveState()
    }

    func setGroupExpanded(id: UUID, isExpanded: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].isExpanded = isExpanded
        saveState()
    }

    func moveFolderToGroup(folderID: UUID, groupID: UUID) {
        guard groups.contains(where: { $0.id == groupID }),
              folders.contains(where: { $0.id == folderID }) else { return }

        // Remove from current group (if any)
        for i in groups.indices where groups[i].folderIDs.contains(folderID) {
            groups[i].folderIDs.removeAll { $0 == folderID }
        }
        // Remove from top-level sidebar order
        sidebarOrder.removeAll { $0 == .folder(folderID) }

        // Add to target group
        if let groupIndex = groups.firstIndex(where: { $0.id == groupID }) {
            groups[groupIndex].folderIDs.append(folderID)
        }
        saveState()
    }

    func moveFolderOutOfGroup(folderID: UUID, atSidebarIndex: Int? = nil) {
        guard folders.contains(where: { $0.id == folderID }) else { return }

        // Remove from any group
        for i in groups.indices where groups[i].folderIDs.contains(folderID) {
            groups[i].folderIDs.removeAll { $0 == folderID }
        }
        // Remove if already in sidebar order (shouldn't be, but be safe)
        sidebarOrder.removeAll { $0 == .folder(folderID) }

        // Insert at specified position or append
        let item = SidebarItem.folder(folderID)
        if let idx = atSidebarIndex, sidebarOrder.indices.contains(idx) {
            sidebarOrder.insert(item, at: idx)
        } else {
            sidebarOrder.append(item)
        }
        saveState()
    }

    func moveSidebarItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sidebarOrder.indices.contains(sourceIndex),
              sidebarOrder.indices.contains(destinationIndex) else { return }
        let item = sidebarOrder.remove(at: sourceIndex)
        sidebarOrder.insert(item, at: destinationIndex)
        saveState()
    }

    func moveFolderWithinGroup(groupID: UUID, from sourceIndex: Int, to destinationIndex: Int) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
              sourceIndex != destinationIndex,
              groups[groupIndex].folderIDs.indices.contains(sourceIndex),
              groups[groupIndex].folderIDs.indices.contains(destinationIndex) else { return }
        let folderID = groups[groupIndex].folderIDs.remove(at: sourceIndex)
        groups[groupIndex].folderIDs.insert(folderID, at: destinationIndex)
        saveState()
    }

    /// Returns the group that contains a given folder, if any.
    func group(forFolderID folderID: UUID) -> FolderGroup? {
        groups.first { $0.folderIDs.contains(folderID) }
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

    func selectNextSessionNeedingAttention(revealInSidebar: Bool = false) {
        guard !sessionsNeedingAttention.isEmpty else { return }
        let ordered = allSessionIDsOrdered.filter { sessionsNeedingAttention.contains($0) }
        guard !ordered.isEmpty else { return }

        if let current = selectedSessionID, let idx = ordered.firstIndex(of: current) {
            // Cycle to next attention session after current
            selectSession(id: ordered[(idx + 1) % ordered.count], revealInSidebar: revealInSidebar)
        } else if let current = selectedSessionID,
                  let currentGlobal = allSessionIDsOrdered.firstIndex(of: current) {
            // Pick the first attention session after the current position
            if let next = ordered.first(where: { id in
                guard let idx = allSessionIDsOrdered.firstIndex(of: id) else { return false }
                return idx > currentGlobal
            }) ?? ordered.first {
                selectSession(id: next, revealInSidebar: revealInSidebar)
            }
        } else {
            if let next = ordered.first {
                selectSession(id: next, revealInSidebar: revealInSidebar)
            }
        }
    }

    // MARK: - MRU Session Switcher

    private func updateMRUOrder(selectedID: UUID) {
        sessionMRUOrder.removeAll { $0 == selectedID }
        sessionMRUOrder.insert(selectedID, at: 0)
    }

    func recordSessionKeyboardInput(sessionID: UUID, at date: Date = Date()) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        resetInputSessionTraversal()

        let shouldRefreshTimestamp = sessionLastInputAt[sessionID].map {
            date.timeIntervalSince($0) >= 1
        } ?? true
        if shouldRefreshTimestamp {
            sessionLastInputAt[sessionID] = date
        }

        let orderChanged = sessionInputMRUOrder.first != sessionID
        if orderChanged {
            sessionInputMRUOrder.removeAll { $0 == sessionID }
            sessionInputMRUOrder.insert(sessionID, at: 0)
        }

        if shouldRefreshTimestamp || orderChanged {
            scheduleSave()
        }
    }

    func selectMostRecentInputSession() {
        let nextIndex: Int
        if let inputSessionTraversalIndex {
            nextIndex = inputSessionTraversalIndex + 1
        } else {
            inputSessionTraversal = sessionInputMRUOrder.filter { id in
                id != selectedSessionID && sessions.contains { $0.id == id }
            }
            nextIndex = 0
        }

        guard inputSessionTraversal.indices.contains(nextIndex) else { return }
        inputSessionTraversalIndex = nextIndex

        isSelectingInputSessionFromTraversal = true
        selectedSessionID = inputSessionTraversal[nextIndex]
        isSelectingInputSessionFromTraversal = false
    }

    private func resetInputSessionTraversal() {
        inputSessionTraversal.removeAll(keepingCapacity: true)
        inputSessionTraversalIndex = nil
    }

    /// Sessions in MRU order with display info for the switcher overlay.
    var sessionSwitcherItems: [(id: UUID, title: String, folderName: String?, branchName: String?, sandboxName: String?)] {
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let folderByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let validIDs = sessionMRUOrder.filter { sessionByID[$0] != nil }
        return validIDs.compactMap { id in
            guard let session = sessionByID[id] else { return nil }
            let folder = folderByID[session.folderID]
            return (
                id: id,
                title: displayState(for: id)?.title ?? session.title,
                folderName: folder?.name,
                branchName: gitStatus(forSession: session)?.currentBranch ?? session.branchName,
                sandboxName: session.sandboxName
            )
        }
    }

    func beginSessionSwitcher(at date: Date = Date()) {
        let items = sessionSwitcherItems
        guard items.count >= 2 else { return }
        sessionSwitcherReferenceDate = date
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
            selectSession(
                id: items[index].id,
                revealInSidebar: revealSelectedSessionInSidebarOnCtrlTab
            )
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

    // MARK: - Worktree Discovery

    func worktrees(for folderID: UUID) -> [GitWorktree] {
        worktreesByFolderID[folderID] ?? []
    }

    func sessionsForWorktree(folderID: UUID, path: String) -> [TerminalSession] {
        let normalizedPath = GitWorktree.normalizePath(path)
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        guard let folder = folders.first(where: { $0.id == folderID }) else { return [] }
        return folder.sessionIDs.compactMap { sessionByID[$0] }.filter {
            guard let worktreePath = $0.worktreePath else { return false }
            return GitWorktree.normalizePath(worktreePath) == normalizedPath
        }
    }

    func missingWorktreeSessionGroups(for folderID: UUID) -> [MissingWorktreeSessionGroup] {
        guard foldersWithSuccessfulWorktreeDiscovery.contains(folderID) else { return [] }
        let activePaths = Set(worktrees(for: folderID).map(\.normalizedPath))
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        guard let folder = folders.first(where: { $0.id == folderID }) else { return [] }

        var groupOrder: [String] = []
        var grouped: [String: [TerminalSession]] = [:]
        for sessionID in folder.sessionIDs {
            guard let session = sessionByID[sessionID],
                  let path = session.worktreePath else { continue }
            let normalizedPath = GitWorktree.normalizePath(path)
            guard !activePaths.contains(normalizedPath) else { continue }
            if grouped[normalizedPath] == nil {
                groupOrder.append(normalizedPath)
            }
            grouped[normalizedPath, default: []].append(session)
        }

        return groupOrder.compactMap { normalizedPath in
            guard let groupedSessions = grouped[normalizedPath],
                  let first = groupedSessions.first,
                  let path = first.worktreePath else { return nil }
            return MissingWorktreeSessionGroup(
                folderID: folderID,
                path: path,
                normalizedPath: normalizedPath,
                branchName: groupedSessions.compactMap(\.branchName).first,
                sessionIDs: groupedSessions.map(\.id)
            )
        }
    }

    func isWorktreeMissing(for session: TerminalSession) -> Bool {
        guard let path = session.worktreePath,
              foldersWithSuccessfulWorktreeDiscovery.contains(session.folderID)
        else { return false }
        return !Set(worktrees(for: session.folderID).map(\.normalizedPath))
            .contains(GitWorktree.normalizePath(path))
    }

    func refreshWorktrees(folderIDs: Set<UUID>? = nil) {
        let requestedFolders = folders.filter {
            $0.isGitRepo
                && $0.pathExists
                && !worktreeDiscoveryInProgress.contains($0.id)
                && (folderIDs == nil || folderIDs!.contains($0.id))
        }
        guard !requestedFolders.isEmpty else { return }

        for folder in requestedFolders {
            let generation = (worktreeRefreshGenerationByFolderID[folder.id] ?? 0) &+ 1
            worktreeRefreshGenerationByFolderID[folder.id] = generation
            worktreeDiscoveryInProgress.insert(folder.id)

            let folderID = folder.id
            let folderPath = folder.path
            let normalizedFolderPath = GitWorktree.normalizePath(folderPath)
            let discoveryService = worktreeDiscoveryService
            let sessionCandidates = sessions.filter {
                $0.folderID == folderID && $0.worktreePath != nil
            }.compactMap { session -> (id: UUID, tmuxName: String, normalizedPath: String)? in
                guard let path = session.worktreePath else { return nil }
                return (
                    id: session.id,
                    tmuxName: session.tmuxSessionName,
                    normalizedPath: GitWorktree.normalizePath(path)
                )
            }

            Task.detached {
                let result: Result<([GitWorktree], Set<UUID>), Error>
                do {
                    let discovered = try discoveryService.listWorktrees(folderPath, folderID)
                    let active = Self.activeDiscoveredWorktrees(
                        discovered,
                        normalizedFolderPath: normalizedFolderPath
                    )

                    let activePaths = Set(active.map(\.normalizedPath))
                    let missingCandidates = sessionCandidates.filter {
                        !activePaths.contains($0.normalizedPath)
                    }
                    let existingTmuxNames = discoveryService.liveTmuxSessionNames()
                    let liveMissingIDs = Set(missingCandidates.compactMap {
                        existingTmuxNames.contains($0.tmuxName) ? $0.id : nil
                    })
                    result = .success((active, liveMissingIDs))
                } catch {
                    result = .failure(error)
                }

                await MainActor.run { [weak self] in
                    self?.applyWorktreeDiscoveryResult(
                        result,
                        folderID: folderID,
                        generation: generation
                    )
                }
            }
        }
    }

    nonisolated static func activeDiscoveredWorktrees(
        _ discovered: [GitWorktree],
        normalizedFolderPath: String
    ) -> [GitWorktree] {
        var seen: Set<String> = []
        return discovered.filter { worktree in
            var isDirectory: ObjCBool = false
            guard worktree.normalizedPath != normalizedFolderPath,
                  !worktree.isBare,
                  !worktree.isPrunable,
                  FileManager.default.fileExists(
                    atPath: worktree.path,
                    isDirectory: &isDirectory
                  ),
                  isDirectory.boolValue,
                  seen.insert(worktree.normalizedPath).inserted
            else { return false }
            return true
        }.sorted {
            let nameOrder = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if nameOrder == .orderedSame {
                return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
            return nameOrder == .orderedAscending
        }
    }

    func applyWorktreeDiscoveryResult(
        _ result: Result<([GitWorktree], Set<UUID>), Error>,
        folderID: UUID,
        generation: UInt64
    ) {
        guard worktreeRefreshGenerationByFolderID[folderID] == generation,
              folders.contains(where: { $0.id == folderID })
        else { return }

        worktreeDiscoveryInProgress.remove(folderID)
        switch result {
        case .failure(let error):
            worktreeDiscoveryErrors[folderID] = error.localizedDescription
        case .success(let payload):
            let (worktrees, liveMissingSessionIDs) = payload
            let previousPaths = Set((worktreesByFolderID[folderID] ?? []).map(\.normalizedPath))
            let currentPaths = Set(worktrees.map(\.normalizedPath))
            worktreesByFolderID[folderID] = worktrees
            worktreeDiscoveryErrors.removeValue(forKey: folderID)
            foldersWithSuccessfulWorktreeDiscovery.insert(folderID)

            let staleSessionIDs = sessions.compactMap { session -> UUID? in
                guard session.folderID == folderID,
                      let path = session.worktreePath,
                      !currentPaths.contains(GitWorktree.normalizePath(path)),
                      !liveMissingSessionIDs.contains(session.id)
                else { return nil }
                return session.id
            }
            for sessionID in staleSessionIDs {
                removeSessionRecord(
                    id: sessionID,
                    save: false,
                    updateGitTracking: false
                )
            }
            if !staleSessionIDs.isEmpty {
                saveState()
            }

            if previousPaths != currentPaths {
                worktreeTrackingReconciliationNeeded = true
                let addedPaths = currentPaths.subtracting(previousPaths)
                pendingWorktreeStatusRefreshPaths.formUnion(
                    worktrees
                        .filter { addedPaths.contains($0.normalizedPath) }
                        .map(\.path)
                )
            }
        }

        // A refresh can cover many folders. Rebuilding the watcher path cache and
        // refreshing every Git status for each individual result makes startup
        // quadratic in the number of repositories. Reconcile once after the whole
        // in-flight batch has completed, and only fetch status for newly tracked
        // worktrees.
        if worktreeDiscoveryInProgress.isEmpty, worktreeTrackingReconciliationNeeded {
            let statusPaths = Array(pendingWorktreeStatusRefreshPaths)
            worktreeTrackingReconciliationNeeded = false
            pendingWorktreeStatusRefreshPaths.removeAll()
            updateGitFileWatcher()
            refreshGitStatuses(for: statusPaths)
        }
    }

    func scheduleWorktreeRefresh(folderIDs: Set<UUID>? = nil) {
        worktreeRefreshDebounce?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshWorktrees(folderIDs: folderIDs)
            }
        }
        worktreeRefreshDebounce = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func removeWorktree(folderID: UUID, path: String) {
        guard let folder = folders.first(where: { $0.id == folderID }) else { return }
        let normalizedPath = GitWorktree.normalizePath(path)
        guard normalizedPath != GitWorktree.normalizePath(folder.path),
              let worktree = worktrees(for: folderID).first(where: {
                  $0.normalizedPath == normalizedPath
              }),
              !worktree.isLocked,
              worktreeRemovalInProgress.insert(worktree.id).inserted
        else { return }

        let sessionSnapshots = sessionsForWorktree(folderID: folderID, path: path)
            .map { (id: $0.id, tmuxName: $0.tmuxSessionName) }
        let worktreeID = worktree.id

        Task.detached {
            do {
                try GitService.removeWorktree(
                    repoPath: folder.path,
                    worktreePath: worktree.path,
                    force: false
                )
            } catch {
                await MainActor.run { [weak self] in
                    self?.worktreeRemovalInProgress.remove(worktreeID)
                    self?.errorMessage = "Failed to remove worktree: \(error.localizedDescription)"
                }
                return
            }

            for session in sessionSnapshots {
                try? TmuxService.killSession(name: session.tmuxName)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                for session in sessionSnapshots {
                    self.removeSessionRecord(id: session.id, save: false)
                }
                if !sessionSnapshots.isEmpty {
                    self.saveState()
                }
                self.worktreeRemovalInProgress.remove(worktreeID)
                self.refreshWorktrees(folderIDs: [folderID])
                self.updateGitFileWatcher()
                self.refreshGitStatuses()
            }
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

    /// Re-create tmux sessions that were killed externally while the app was not running,
    /// and kill orphaned tmux sessions that no longer have a matching app session.
    private func restoreTmuxSessions() {
        guard tmuxAvailable else { return }
        let sessionsSnapshot = sessions.compactMap { session -> (name: String, cwd: String, shellCommand: String?)? in
            let cwd = session.worktreePath ?? session.workingDirectory
            if session.worktreePath != nil, !FileManager.default.fileExists(atPath: cwd) {
                return nil
            }
            let shellCommand: String? = if let sandboxName = session.sandboxName {
                SbxService.execCommand(
                    sandboxName: sandboxName,
                    cwd: cwd,
                    environmentVariables: resolvedEnvironmentVariables(for: sandboxName)
                )
            } else {
                nil
            }
            return (name: session.tmuxSessionName, cwd: cwd, shellCommand: shellCommand)
        }
        let knownNames = Set(sessions.map(\.tmuxSessionName))
        Task.detached {
            let existingSessions = Set(TmuxService.listSessions())

            // Restore missing sessions
            for session in sessionsSnapshot {
                if !existingSessions.contains(session.name) {
                    do {
                        try TmuxService.createSession(name: session.name, cwd: session.cwd, shellCommand: session.shellCommand)
                    } catch {
                        print("[TermHub] Failed to restore tmux session '\(session.name)': \(error)")
                    }
                }
            }

            // Kill orphaned sessions on the termhub socket
            let orphans = existingSessions.filter { !knownNames.contains($0) }
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

    func refreshSelectedSessionPullRequest() {
        pullRequestRefreshSequence &+= 1
        let sequence = pullRequestRefreshSequence

        guard let sessionID = selectedSessionID,
              let repositoryPath = selectedSessionGitPath,
              folderForSelectedSession?.isGitRepo == true
        else {
            selectedSessionPullRequestURL = nil
            isSelectedSessionPullRequestLoading = false
            return
        }

        selectedSessionPullRequestURL = nil
        isSelectedSessionPullRequestLoading = true
        let lookup = pullRequestLookupService.openPullRequestURL

        Task.detached {
            let url = lookup(repositoryPath)
            await MainActor.run { [weak self] in
                guard let self,
                      self.pullRequestRefreshSequence == sequence,
                      self.selectedSessionID == sessionID
                else { return }
                self.selectedSessionPullRequestURL = url
                self.isSelectedSessionPullRequestLoading = false
            }
        }
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
        let watchPathsByTrackedPath = refreshGitWatchPathCache()
        let watchedPaths = Array(Set(watchPathsByTrackedPath.values.flatMap { $0 })).sorted()
        pruneUntrackedGitStatuses()

        gitFileWatcher.start(paths: watchedPaths) { [weak self] changedPaths in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let affectedPaths = self.affectedTrackedGitPaths(for: changedPaths)
                // FSEvents can report a path with a different spelling (for example
                // through a symlink), so use a full refresh if the path mapping did
                // not identify a tracked repository. The watcher already limits
                // this to changes below one of the tracked paths.
                self.refreshGitStatuses(for: affectedPaths.isEmpty ? self.trackedGitPaths() : affectedPaths)
                let affectedFolderIDs: Set<UUID> = Set(self.folders.compactMap { folder -> UUID? in
                    guard folder.isGitRepo else { return nil }
                    let watchPaths = self.gitWatchPathsByTrackedPath[folder.path] ?? [folder.path]
                    return watchPaths.contains(where: { watchedPath in
                        changedPaths.contains(where: {
                            $0 == watchedPath || $0.hasPrefix(watchedPath + "/")
                        })
                    }) ? folder.id : nil
                })
                self.scheduleWorktreeRefresh(
                    folderIDs: affectedFolderIDs.isEmpty ? nil : affectedFolderIDs
                )
                if self.currentDetailTab == .gitDiff,
                   let currentPath = self.selectedSessionGitPath,
                   (affectedPaths.isEmpty || affectedPaths.contains(currentPath)) {
                    self.loadDiffForCurrentSession()
                }
            }
        }
    }

    func refreshGitStatuses(for paths: [String]? = nil) {
        let trackedPathSet = Set(trackedGitPaths())
        let paths = Array(Set(paths ?? Array(trackedPathSet)))
            .filter { trackedPathSet.contains($0) }
            .sorted()
        guard !paths.isEmpty else { return }

        gitStatusRefreshSequence &+= 1
        let sequence = gitStatusRefreshSequence
        for path in paths {
            latestGitStatusRefreshByPath[path] = sequence
        }

        Task.detached {
            // Run git status calls in parallel instead of sequentially.
            var results: [(String, Result<GitStatus, Error>)] = []
            await withTaskGroup(of: (String, Result<GitStatus, Error>).self) { group in
                for path in paths {
                    group.addTask {
                        do {
                            return (path, .success(try GitService.status(path: path)))
                        } catch {
                            return (path, .failure(error))
                        }
                    }
                }
                for await result in group {
                    results.append(result)
                }
            }
            await MainActor.run { @MainActor [weak self] in
                guard let self else { return }
                let currentlyTracked = Set(self.trackedGitPaths())
                var selectedBranchChanged = false
                for (path, result) in results {
                    // Ignore a result if a newer refresh was started for this path,
                    // or if the folder/worktree was removed while git was running.
                    guard self.latestGitStatusRefreshByPath[path] == sequence,
                          currentlyTracked.contains(path) else { continue }
                    switch result {
                    case .success(let status):
                        if path == self.selectedSessionGitPath,
                           self.gitStatuses[path]?.currentBranch != status.currentBranch {
                            selectedBranchChanged = true
                        }
                        if self.gitStatuses[path] != status {
                            self.gitStatuses[path] = status
                        }
                    case .failure(let error):
                        print("[TermHub] Git status refresh failed for '\(path)': \(error.localizedDescription); keeping previous status")
                    }
                }
                // A targeted refresh is only a partial snapshot. Remove entries
                // based on the actual tracked paths, never based on this result set.
                self.pruneUntrackedGitStatuses(trackedPaths: currentlyTracked)
                if selectedBranchChanged {
                    self.refreshSelectedSessionPullRequest()
                }
            }
        }
    }

    private func pruneUntrackedGitStatuses(trackedPaths: Set<String>? = nil) {
        let trackedPaths = trackedPaths ?? Set(trackedGitPaths())
        for key in Array(gitStatuses.keys) where !trackedPaths.contains(key) {
            gitStatuses.removeValue(forKey: key)
        }
    }

    private var selectedSessionGitPath: String? {
        guard let session = selectedSession else { return nil }
        return session.worktreePath
            ?? folders.first(where: { $0.id == session.folderID })?.path
    }

    func affectedTrackedGitPaths(for changedPaths: [String]) -> [String] {
        let trackedPaths = trackedGitPaths()
        guard !trackedPaths.isEmpty, !changedPaths.isEmpty else { return [] }

        let watchedPathsByTrackedPath = currentGitWatchPathsByTrackedPath(for: trackedPaths)
        var affected: [String] = []
        for trackedPath in trackedPaths {
            let watchedPaths = watchedPathsByTrackedPath[trackedPath] ?? [trackedPath]
            if watchedPaths.contains(where: { watchedPath in
                changedPaths.contains(where: { changedPath in
                    changedPath == watchedPath || changedPath.hasPrefix(watchedPath + "/")
                })
            }) {
                affected.append(trackedPath)
            }
        }
        return affected
    }

    func trackedGitPaths() -> [String] {
        var seen: Set<String> = []
        var paths: [String] = []

        for folder in folders where folder.isGitRepo && folder.pathExists {
            if seen.insert(folder.path).inserted {
                paths.append(folder.path)
            }
        }

        for worktrees in worktreesByFolderID.values {
            for worktree in worktrees where FileManager.default.fileExists(atPath: worktree.path) {
                if seen.insert(worktree.path).inserted {
                    paths.append(worktree.path)
                }
            }
        }

        return paths
    }

    private func currentGitWatchPathsByTrackedPath(for trackedPaths: [String]) -> [String: [String]] {
        let trackedPathSet = Set(trackedPaths)
        if !gitWatchPathsByTrackedPath.isEmpty, Set(gitWatchPathsByTrackedPath.keys) == trackedPathSet {
            return gitWatchPathsByTrackedPath
        }
        return refreshGitWatchPathCache(for: trackedPaths)
    }

    @discardableResult
    private func refreshGitWatchPathCache(for trackedPaths: [String]? = nil) -> [String: [String]] {
        let trackedPaths = trackedPaths ?? trackedGitPaths()
        let mapping = Dictionary(uniqueKeysWithValues: trackedPaths.map { path in
            (path, GitService.gitMetadataWatchPaths(path: path))
        })
        gitWatchPathsByTrackedPath = mapping
        return mapping
    }

    func applyDetectedGitRepos(atPaths detectedPaths: [String]) {
        guard !detectedPaths.isEmpty else { return }

        let detectedSet = Set(detectedPaths)
        var changedPaths: [String] = []
        for index in folders.indices {
            let path = folders[index].path
            guard detectedSet.contains(path), folders[index].isGitRepo == false else { continue }
            folders[index].isGitRepo = true
            changedPaths.append(path)
        }

        guard !changedPaths.isEmpty else { return }
        saveState()
        refreshGitStatuses(for: changedPaths)
        updateGitFileWatcher()
        let changedFolderIDs = Set(folders.filter { changedPaths.contains($0.path) }.map(\.id))
        refreshWorktrees(folderIDs: changedFolderIDs)
    }

    /// Detects git repo status for folders that don't have it persisted yet.
    /// Runs detection off the main thread to avoid blocking the UI at startup.
    private func detectGitRepos() {
        let foldersNeedingDetection = folders.enumerated().filter { !$0.element.isGitRepo && $0.element.pathExists }
        guard !foldersNeedingDetection.isEmpty else { return }

        let paths = foldersNeedingDetection.map { (index: $0.offset, path: $0.element.path) }
        Task.detached {
            var detectedPaths: [String] = []
            for item in paths {
                let isGit = GitService.isGitRepo(path: item.path)
                if isGit {
                    detectedPaths.append(item.path)
                }
            }
            await MainActor.run { [weak self] in
                self?.applyDetectedGitRepos(atPaths: detectedPaths)
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
        // Codex emits MCP worker diagnostics on stderr while a request can still
        // complete successfully. Keep those diagnostics for failure reporting,
        // but do not briefly replace the active response status with them.
        if assistantProvider != .codex {
            if let lastLine = trimmed.split(separator: "\n").last {
                assistantStatusMessage = String(lastLine)
            } else {
                assistantStatusMessage = trimmed
            }
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
            sessionInputMRUOrder = (state.sessionInputMRUOrder ?? []).filter { validSessionIDs.contains($0) }
            sessionLastInputAt = (state.sessionLastInputAt ?? [:]).filter {
                validSessionIDs.contains($0.key)
            }
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

            // Restore groups and sidebar order with migration for existing state
            groups = state.groups ?? []
            let loadedOrder = state.sidebarOrder ?? []
            if loadedOrder.isEmpty, !folders.isEmpty {
                // Migration: build sidebarOrder from existing folder order
                sidebarOrder = folders.map { .folder($0.id) }
            } else {
                sidebarOrder = loadedOrder
                // Ensure all ungrouped folders appear in sidebarOrder
                let groupedFolderIDs = Set(groups.flatMap(\.folderIDs))
                let orderedIDs = Set(sidebarOrder.compactMap { item -> UUID? in
                    if case .folder(let id) = item { return id }
                    return nil
                })
                for folder in folders where !groupedFolderIDs.contains(folder.id) && !orderedIDs.contains(folder.id) {
                    sidebarOrder.append(.folder(folder.id))
                }
                // Ensure all groups appear in sidebarOrder
                let orderedGroupIDs = Set(sidebarOrder.compactMap { item -> UUID? in
                    if case .group(let id) = item { return id }
                    return nil
                })
                for group in groups where !orderedGroupIDs.contains(group.id) {
                    sidebarOrder.append(.group(group.id))
                }
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
            sessionInputMRUOrder: sessionInputMRUOrder,
            sessionLastInputAt: sessionLastInputAt,
            sandboxEnvironmentKeys: sandboxEnvironmentKeys.isEmpty ? nil : sandboxEnvironmentKeys,
            assistantMessages: assistantMessages.isEmpty ? nil : assistantMessages,
            assistantSessionId: assistantService.sessionID(for: .claude),
            assistantSessionIdsByProvider: assistantService.sessionIDs(),
            assistantAllowedToolsByProvider: assistantAllowedToolsByProvider,
            groups: groups.isEmpty ? nil : groups,
            sidebarOrder: sidebarOrder.isEmpty ? nil : sidebarOrder
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
        guard let path = detectCLIPath(for: provider) else { return false }
        return isCLIAvailable(for: provider, executablePath: path)
    }

    static func isCLIAvailable(for provider: AssistantProvider, executablePath: String) -> Bool {
        let path = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return false }
        return true
    }

    static func detectCLIPath(for provider: AssistantProvider) -> String? {
        if let override = commandExistsOverride {
            return override(provider.commandName) ? provider.commandName : nil
        }
        let fileManager = FileManager.default
        let candidates: [String]
        switch provider {
        case .claude:
            candidates = [
                "\(fileManager.homeDirectoryForCurrentUser.path)/.local/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
            ]
        case .copilot:
            candidates = [
                "/opt/homebrew/bin/copilot",
                "/usr/local/bin/copilot",
            ]
        case .codex:
            candidates = [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
            ]
        }

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return commandPath(for: provider.commandName)
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
        workingDirectory: String?,
        executablePath: String? = nil
    ) throws -> [String] {
        // If a previous process is still running, terminate it first.
        if process?.isRunning == true {
            process?.terminate()
            process?.waitUntilExit()
        }
        cleanupPipes()

        guard let executablePath = executablePath ?? Self.detectCLIPath(for: provider),
              Self.isCLIAvailable(for: provider, executablePath: executablePath)
        else {
            throw AssistantServiceError.cliNotFound(provider)
        }

        let isFirstMessage = provider == .codex || sessionIDsByProvider[provider.rawValue] == nil
        let sessionID: UUID
        if provider == .codex {
            sessionID = UUID()
        } else if let existing = sessionIDsByProvider[provider.rawValue] {
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
        process.arguments = [executablePath] + build.args.dropFirst()
        CommandLogger.log(executablePath: "/usr/bin/env", arguments: [executablePath] + build.args.dropFirst())

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
            guard let self, self.process === proc else { return }
            self.cleanupPipes()
            self.onExit?(proc.terminationStatus)
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
        let process = self.process
        self.process = nil
        cleanupPipes()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private func cleanupPipes() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private static func commandPath(for command: String) -> String? {
        if let override = commandExistsOverride {
            return override(command) ? command : nil
        }
        CommandLogger.log(executablePath: "/usr/bin/which", arguments: [command])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
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
        case .codex:
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
        case .codex:
            args = ["codex", "exec"]
            if !resolvedModel.isEmpty { args += ["--model", resolvedModel] }
            args += [
                "--skip-git-repo-check",
                "--color", "never"
            ]
            if !resolvedEffort.isEmpty {
                args += ["--config", "model_reasoning_effort=\"\(resolvedEffort)\""]
            }
            if mcpEnabled {
                // The assistant UI launches codex exec without an interactive stdin,
                // so MCP calls cannot wait for a terminal approval prompt.
                args += ["--config", "mcp_servers.termhub.default_tools_approval_mode=\"auto\""]
                notices.append("Codex loads MCP servers from ~/.codex/config.toml. TermHub does not inject MCP configuration per request.")
            }
            if !safeToolsList.isEmpty || !ignoredToolsList.isEmpty {
                notices.append("Ignored Codex Allowed Tools setting. `codex exec` does not expose a matching allowlist flag.")
            }
            args += [text]
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
