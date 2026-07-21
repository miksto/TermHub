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
    private static var current: AssistantPanel?

    private let appState: AppState
    private let terminal: LocalProcessTerminalView
    private var started = false
    private var resizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?

    private init(contentRect: NSRect, appState: AppState) {
        self.appState = appState
        terminal = LocalProcessTerminalView(frame: .init(x: 0, y: 0, width: 900, height: 620))
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

        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        terminal.nativeForegroundColor = NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0)
        terminal.optionAsMetaKey = appState.optionAsMetaKey
        terminal.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(terminal)
        let preferredWidth = terminal.widthAnchor.constraint(equalToConstant: 900)
        let preferredHeight = terminal.heightAnchor.constraint(equalToConstant: 620)
        preferredWidth.priority = .defaultHigh
        preferredHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            terminal.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            terminal.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            preferredWidth,
            preferredHeight,
            terminal.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, constant: -40),
            terminal.heightAnchor.constraint(lessThanOrEqualTo: overlay.heightAnchor, constant: -40),
        ])
        contentView = overlay
    }

    static func show(in parentWindow: NSWindow, appState: AppState) {
        if let panel = current {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.terminal)
            return
        }

        let panel = AssistantPanel(contentRect: parentWindow.frame, appState: appState)
        let syncFrame: @MainActor () -> Void = { [weak panel, weak parentWindow] in
            guard let panel, let parentWindow else { return }
            panel.setFrame(parentWindow.frame, display: true)
        }
        panel.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: parentWindow,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { syncFrame() }
        }
        panel.moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: parentWindow,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { syncFrame() }
        }
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        current = panel
        panel.makeFirstResponder(panel.terminal)
        panel.startCodex()
    }

    static func dismiss() {
        guard let panel = current else { return }
        // Keep the terminal and Codex process alive while hidden so reopening
        // the assistant resumes the same interactive conversation.
        panel.orderOut(nil)
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

    private func startCodex() {
        guard !started else { return }
        let codexPath = appState.assistantCLIPaths[AssistantProvider.codex.rawValue]
            ?? AssistantService.detectCLIPath(for: .codex)
            ?? "codex"
        let session = appState.selectedSession
        let workingDirectory = session?.worktreePath ?? session?.workingDirectory

        var arguments: [String] = []
        let model = appState.assistantModelByProvider[AssistantProvider.codex.rawValue] ?? ""
        if !model.isEmpty {
            arguments += ["--model", model]
        }

        terminal.startProcess(
            executable: codexPath,
            args: arguments,
            environment: ShellEnvironment.shellEnvironment.map { "\($0.key)=\($0.value)" },
            execName: "codex",
            currentDirectory: workingDirectory
        )
        started = true
    }
}
