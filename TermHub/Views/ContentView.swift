import AppKit
import SwiftUI
import SwiftTerm

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?

    var body: some View {
        mainContent
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }

                ToolbarItem(placement: .primaryAction) {
                    SandboxToolbarButton()
                }

                ToolbarItem(placement: .automatic) {
                    SessionToolbarTitleView()
                }
            }
            .sheet(isPresented: Binding(
                get: { appState.showKeyboardShortcuts },
                set: { appState.showKeyboardShortcuts = $0 }
            )) {
                KeyboardShortcutsSheet()
            }
            .onChange(of: appState.showSettings) { _, show in
                if show {
                    if let window = NSApp.mainWindow {
                        SettingsPanel.show(in: window, appState: appState)
                    }
                } else {
                    SettingsPanel.dismiss()
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { appState.pendingSandboxPickerContext != nil },
                    set: { if !$0 { appState.pendingSandboxPickerContext = nil } }
                )
            ) {
                if let ctx = appState.pendingSandboxPickerContext {
                    ShellSandboxPickerSheet(
                        folderID: ctx.folderID,
                        folderName: ctx.folderName,
                        cwd: ctx.cwd,
                        worktreePath: ctx.worktreePath,
                        branchName: ctx.branchName,
                        initialSandboxName: appState.lastUsedSandboxName
                    )
                }
            }
            .modifier(ContentViewAlerts())
            .onChange(of: appState.showSandboxManager) { _, show in
                if show {
                    if let window = NSApp.mainWindow {
                        SandboxManagerPanel.show(in: window, appState: appState)
                    }
                } else {
                    SandboxManagerPanel.dismiss()
                }
            }
            .onChange(of: appState.showAssistant) { _, show in
                if show {
                    if let window = NSApp.mainWindow {
                        AssistantPanel.show(in: window, appState: appState)
                    }
                } else {
                    AssistantPanel.dismiss()
                }
            }
            .onAppear { installSessionSwitcherMonitors() }
            .onDisappear {
                AssistantPanel.dismiss()
                removeSessionSwitcherMonitors()
            }
    }

    private var mainContent: some View {
        ZStack {
            VStack(spacing: 0) {
                if !appState.tmuxAvailable {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("tmux not found — sessions won't persist across restarts")
                    }
                    .font(.callout)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(SwiftUI.Color.orange.opacity(0.85))
                }

                NavigationSplitView {
                    SidebarView()
                } detail: {
                    if appState.selectedSessionID != nil {
                        TerminalContainerView(selectedSessionID: appState.selectedSessionID)
                    } else {
                        Text("Select or create a session")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationSplitViewStyle(.balanced)
            }

            if appState.showCommandPalette {
                CommandPaletteOverlay()
                    .transition(.opacity)
            }

            if appState.isSessionSwitcherActive {
                SessionSwitcherOverlay()
                    .transition(.opacity)
            }

        }
        .animation(.easeOut(duration: 0.15), value: appState.showCommandPalette)
        .animation(.easeOut(duration: 0.1), value: appState.isSessionSwitcherActive)
    }

    private func installSessionSwitcherMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape dismisses overlays before the terminal can consume it

            // Cmd+Shift+Backspace jumps to the most recently keyboard-interacted session.
            if event.keyCode == 51,
               event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.shift) {
                appState.selectMostRecentInputSession()
                return nil
            }

            // Ctrl+Space toggles assistant
            if event.keyCode == 49, event.modifierFlags.contains(.control) {
                appState.toggleAssistant()
                return nil
            }

            // Ctrl+Tab (keyCode 48 = Tab)
            guard event.keyCode == 48,
                  event.modifierFlags.contains(.control) else {
                return event
            }
            let reverse = event.modifierFlags.contains(.shift)
            if appState.isSessionSwitcherActive {
                if reverse {
                    appState.reverseSessionSwitcher()
                } else {
                    appState.advanceSessionSwitcher()
                }
            } else {
                if reverse {
                    // For Ctrl+Shift+Tab when not active, begin and immediately reverse
                    appState.beginSessionSwitcher()
                } else {
                    appState.beginSessionSwitcher()
                }
            }
            return nil
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            if appState.isSessionSwitcherActive,
               !event.modifierFlags.contains(.control) {
                appState.commitSessionSwitcher()
            }
            return event
        }
    }

    private func removeSessionSwitcherMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
    }
}

// MARK: - Alerts

private struct ContentViewAlerts: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .alert(
                "Error",
                isPresented: Binding(
                    get: { appState.errorMessage != nil },
                    set: { if !$0 { appState.errorMessage = nil } }
                ),
                presenting: appState.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {
                    appState.errorMessage = nil
                }
            } message: { message in
                Text(message)
            }
            .alert(
                "Remove Folder",
                isPresented: Binding(
                    get: { appState.pendingRemoveFolderID != nil },
                    set: { if !$0 { appState.pendingRemoveFolderID = nil } }
                ),
                presenting: appState.pendingRemoveFolderID.flatMap { id in
                    appState.folders.first(where: { $0.id == id })
                }
            ) { folder in
                Button("Cancel", role: .cancel) {
                    appState.pendingRemoveFolderID = nil
                }
                Button("Remove", role: .destructive) {
                    appState.removeFolder(id: folder.id)
                    appState.pendingRemoveFolderID = nil
                }
            } message: { folder in
                let sessionCount = appState.sessions.filter { $0.folderID == folder.id }.count
                let worktreeCount = appState.sessions.filter { $0.folderID == folder.id && $0.worktreePath != nil }.count
                if worktreeCount > 0 {
                    Text("This will close \(sessionCount) tmux session(s) and remove \(worktreeCount) worktree(s) for \"\(folder.name)\".")
                } else {
                    Text("This will close \(sessionCount) tmux session(s) for \"\(folder.name)\".")
                }
            }
    }
}

// MARK: - Sandbox Toolbar Button

struct SandboxToolbarButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let hasRunning = appState.sandboxes.contains { $0.isRunning }
        let hasSandboxSessions = appState.sessions.contains { $0.isSandboxSession }
        let color: SwiftUI.Color = hasRunning ? .green : hasSandboxSessions ? .orange : .secondary

        Button {
            appState.showSandboxManager.toggle()
        } label: {
            Image(systemName: "shippingbox")
                .foregroundStyle(color)
        }
        .help("Sandbox Manager")
    }
}

struct SessionToolbarTitleView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let title = Self.toolbarTitle(in: appState) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(SwiftUI.Color(nsColor: .separatorColor))
                    .frame(width: 1, height: 18)

                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 360, alignment: .leading)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .help(title)
        }
    }

    @MainActor
    static func toolbarTitle(in appState: AppState) -> String? {
        guard let session = appState.selectedSession,
              let folder = appState.folders.first(where: { $0.id == session.folderID })
        else { return nil }

        let sessionTitle = appState.displayState(for: session.id)?.title ?? session.title
        return title(groupName: appState.group(forFolderID: folder.id)?.name, repoName: folder.name, sessionTitle: sessionTitle)
    }

    static func title(groupName: String?, repoName: String, sessionTitle: String) -> String {
        [groupName, repoName, sessionTitle]
            .compactMap { $0 }
            .joined(separator: " - ")
    }
}

/// An interactive Codex CLI terminal in its own AppKit panel. Codex's normal
/// terminal UI handles conversation state, approvals, and MCP interaction.
@MainActor
final class AssistantPanel: NSPanel {
    private static var cachedByFolderID: [UUID: AssistantPanel] = [:]
    private static weak var visiblePanel: AssistantPanel?
    private static let codexInstructions = """
        You are the interactive assistant embedded in TermHub, a macOS app for managing terminal sessions, tmux-backed persistent shells, git worktrees, and Docker sandboxes.

        Your process working directory is the parent TermHub folder selected when this assistant was created. Treat that folder as the primary workspace for local coding tasks. TermHub MCP tools remain available for managing all TermHub folders, sessions, worktrees, and sandboxes.

        Help the user with their current workspace and coding tasks. Before creating a worktree or selecting a base ref, use the TermHub MCP's git_branches tool to obtain the repository's actual branch names. When a request concerns Linear issues, projects, planning, or issue status, use the configured Linear MCP tools when relevant. Be concise, explain impactful actions, and preserve the user's intent.
        """

    private let appState: AppState
    private let folderID: UUID
    private let folderPath: String
    private let codexPath: String
    private let codexArguments: [String]
    private let codexEnvironment: [String]
    private let terminal: LocalProcessTerminalView
    private let folderNameLabel: NSTextField
    private var processDelegate: AssistantProcessDelegate?
    private var processIsRunning = false
    private var isCleaningUp = false
    private var resizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?

    private init(
        contentRect: NSRect,
        appState: AppState,
        folder: ManagedFolder,
        codexPath: String,
        codexArguments: [String],
        codexEnvironment: [String]
    ) {
        self.appState = appState
        folderID = folder.id
        folderPath = folder.path
        self.codexPath = codexPath
        self.codexArguments = codexArguments
        self.codexEnvironment = codexEnvironment
        terminal = LocalProcessTerminalView(frame: .init(x: 0, y: 0, width: 900, height: 620))
        folderNameLabel = NSTextField(labelWithString: folder.name)
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isReleasedWhenClosed = false

        let overlay = NSView(frame: contentRect)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        overlay.autoresizingMask = [.width, .height]

        let terminalCard = NSVisualEffectView()
        terminalCard.material = .hudWindow
        terminalCard.blendingMode = .withinWindow
        terminalCard.state = .active
        terminalCard.wantsLayer = true
        terminalCard.layer?.cornerRadius = 12
        terminalCard.layer?.masksToBounds = true
        terminalCard.layer?.borderWidth = 1
        terminalCard.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.8).cgColor
        terminalCard.layer?.shadowColor = NSColor.black.cgColor
        terminalCard.layer?.shadowOpacity = 0.45
        terminalCard.layer?.shadowRadius = 20
        terminalCard.layer?.shadowOffset = .init(width: 0, height: -8)
        terminalCard.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(terminalCard)

        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        terminal.nativeForegroundColor = NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0)
        terminal.optionAsMetaKey = appState.optionAsMetaKey
        terminal.translatesAutoresizingMaskIntoConstraints = false

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        folderNameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        folderNameLabel.textColor = .secondaryLabelColor
        folderNameLabel.lineBreakMode = .byTruncatingTail
        folderNameLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(folderNameLabel)

        terminalCard.addSubview(header)
        terminalCard.addSubview(terminal)
        let preferredWidth = terminalCard.widthAnchor.constraint(equalToConstant: 900)
        let preferredHeight = terminalCard.heightAnchor.constraint(equalToConstant: 620)
        preferredWidth.priority = .defaultHigh
        preferredHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            terminalCard.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            terminalCard.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            preferredWidth,
            preferredHeight,
            terminalCard.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, constant: -40),
            terminalCard.heightAnchor.constraint(lessThanOrEqualTo: overlay.heightAnchor, constant: -40),
            header.leadingAnchor.constraint(equalTo: terminalCard.leadingAnchor, constant: 1),
            header.trailingAnchor.constraint(equalTo: terminalCard.trailingAnchor, constant: -1),
            header.topAnchor.constraint(equalTo: terminalCard.topAnchor, constant: 1),
            header.heightAnchor.constraint(equalToConstant: 30),
            folderNameLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 11),
            folderNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -11),
            folderNameLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            terminal.leadingAnchor.constraint(equalTo: terminalCard.leadingAnchor, constant: 1),
            terminal.trailingAnchor.constraint(equalTo: terminalCard.trailingAnchor, constant: -1),
            terminal.topAnchor.constraint(equalTo: header.bottomAnchor),
            terminal.bottomAnchor.constraint(equalTo: terminalCard.bottomAnchor, constant: -1),
        ])
        contentView = overlay

        let processDelegate = AssistantProcessDelegate(panel: self)
        self.processDelegate = processDelegate
        terminal.processDelegate = processDelegate
        refreshFolderName(folder.name)
    }

    static func show(in parentWindow: NSWindow, appState: AppState) {
        guard let folder = appState.selectedFolder else {
            appState.showAssistant = false
            return
        }
        guard folderPathIsDirectory(folder.path) else {
            appState.showAssistant = false
            return
        }

        if let panel = visiblePanel, panel.folderID != folder.id {
            panel.orderOut(nil)
            visiblePanel = nil
        }

        let panel: AssistantPanel
        if let cached = cachedByFolderID[folder.id] {
            panel = cached
        } else {
            let launchConfiguration = codexLaunchConfiguration(appState: appState)
            panel = AssistantPanel(
                contentRect: parentWindow.frame,
                appState: appState,
                folder: folder,
                codexPath: launchConfiguration.path,
                codexArguments: launchConfiguration.arguments,
                codexEnvironment: launchConfiguration.environment
            )
            cachedByFolderID[folder.id] = panel
            panel.attach(to: parentWindow)
        }

        panel.refreshFolderName(folder.name)
        panel.setFrame(parentWindow.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.terminal)
        panel.startCodexIfNeeded()
        visiblePanel = panel
    }

    static func dismiss() {
        guard let panel = visiblePanel else { return }
        // Keep the terminal and Codex process alive while hidden so reopening
        // the assistant resumes the same interactive conversation.
        panel.orderOut(nil)
        visiblePanel = nil
    }

    static func removeAssistant(for folderID: UUID) {
        guard let panel = cachedByFolderID.removeValue(forKey: folderID) else { return }
        panel.cleanup()
    }

    override func close() {
        appState.showAssistant = false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            appState.showAssistant = false
            return
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { true }

    private static func codexLaunchConfiguration(
        appState: AppState
    ) -> (path: String, arguments: [String], environment: [String]) {
        let codexPath = appState.assistantCLIPaths[AssistantProvider.codex.rawValue]
            ?? AssistantService.detectCLIPath(for: .codex)
            ?? "codex"

        var arguments: [String] = []
        let model = appState.assistantModelByProvider[AssistantProvider.codex.rawValue] ?? ""
        if !model.isEmpty {
            arguments += ["--model", model]
        }
        let escapedInstructions = Self.codexInstructions
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        arguments += ["--config", "developer_instructions=\"\(escapedInstructions)\""]

        return (
            codexPath,
            arguments,
            ShellEnvironment.shellEnvironment.map { "\($0.key)=\($0.value)" }
        )
    }

    private static func folderPathIsDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func attach(to parentWindow: NSWindow) {
        let syncFrame: @MainActor () -> Void = { [weak self, weak parentWindow] in
            guard let self, let parentWindow else { return }
            setFrame(parentWindow.frame, display: true)
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: parentWindow,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { syncFrame() }
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: parentWindow,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { syncFrame() }
        }
        parentWindow.addChildWindow(self, ordered: .above)
    }

    private func refreshFolderName(_ folderName: String) {
        folderNameLabel.stringValue = folderName
        folderNameLabel.setAccessibilityLabel("Assistant for \(folderName)")
    }

    private func startCodexIfNeeded() {
        guard !processIsRunning, !isCleaningUp else { return }
        terminal.startProcess(
            executable: codexPath,
            args: codexArguments,
            environment: codexEnvironment,
            execName: "codex",
            currentDirectory: folderPath
        )
        processIsRunning = true
    }

    fileprivate func processTerminated() {
        guard !isCleaningUp else { return }
        processIsRunning = false
    }

    private func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true

        if Self.visiblePanel === self {
            orderOut(nil)
            Self.visiblePanel = nil
            appState.showAssistant = false
        }
        if processIsRunning {
            terminal.terminate()
            processIsRunning = false
        }
        terminal.processDelegate = nil
        processDelegate = nil
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}

private final class AssistantProcessDelegate: LocalProcessTerminalViewDelegate {
    private weak var panel: AssistantPanel?

    @MainActor
    init(panel: AssistantPanel) {
        self.panel = panel
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        let panel = panel
        Task { @MainActor in
            panel?.processTerminated()
        }
    }
}
