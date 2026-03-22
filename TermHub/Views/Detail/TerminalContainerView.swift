import SwiftUI
import SwiftTerm

extension Notification.Name {
    static let diffDataDidChange = Notification.Name("diffDataDidChange")
}

/// Uses NSViewControllerRepresentable instead of NSViewRepresentable to get
/// proper mouse event delivery. NSViewRepresentable can intercept mouse events
/// before they reach the embedded NSView.
struct TerminalContainerView: NSViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    let selectedSessionID: UUID?

    func makeNSViewController(context: Context) -> TerminalContainerViewController {
        TerminalContainerViewController(appState: appState)
    }

    func updateNSViewController(_ controller: TerminalContainerViewController, context: Context) {
        // Only read lightweight properties to control when SwiftUI triggers this method.
        // Notably, we do NOT read appState.sessions here — title changes would cause
        // unnecessary re-evaluations that interfere with terminal rendering during heavy output.
        let selectedID = selectedSessionID
        let suppressInteraction = appState.showCommandPalette
        let sessionListVersion = appState.sessionListVersion
        let tmuxAvailable = appState.tmuxAvailable

        controller.updateTerminals(
            selectedID: selectedID,
            tmuxAvailable: tmuxAvailable,
            suppressInteraction: suppressInteraction,
            sessionListVersion: sessionListVersion
        )
    }
}

class TerminalContainerViewController: NSViewController {
    private let rootView = NSView()
    private let tabBarView: DetailTabBarNSView
    private let terminalContainer = NSView()
    private let diffContainer = NSView()
    private let appState: AppState
    private var lastSessionListVersion = -1
    private var lastSelectedID: UUID?
    private var lastTmuxAvailable: Bool?
    private var lastSuppressInteraction: Bool?
    private var diffScrollView: NSScrollView?
    private var diffDelegate: DiffTableDelegate?
    private var diffEmptyStateView: NSTextField?
    private var lastDetailTab: DetailTab = .terminal
    private var contentTopToTabBar: NSLayoutConstraint!
    private var contentTopToRoot: NSLayoutConstraint!

    init(appState: AppState) {
        self.appState = appState
        self.tabBarView = DetailTabBarNSView(appState: appState)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let bgColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)

        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = bgColor.cgColor
        self.view = rootView

        // Tab bar at top
        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(tabBarView)

        // Terminal container fills below tab bar
        terminalContainer.wantsLayer = true
        terminalContainer.layer?.backgroundColor = bgColor.cgColor
        terminalContainer.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(terminalContainer)

        // Diff container overlays terminal container
        diffContainer.wantsLayer = true
        diffContainer.layer?.backgroundColor = bgColor.cgColor
        diffContainer.translatesAutoresizingMaskIntoConstraints = false
        diffContainer.isHidden = true
        rootView.addSubview(diffContainer)

        contentTopToTabBar = terminalContainer.topAnchor.constraint(equalTo: tabBarView.bottomAnchor)
        contentTopToRoot = terminalContainer.topAnchor.constraint(equalTo: rootView.topAnchor)

        NSLayoutConstraint.activate([
            tabBarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            tabBarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: 32),

            terminalContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            terminalContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentTopToTabBar,
            terminalContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            diffContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            diffContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            diffContainer.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            diffContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])

        setupDiffTableView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        let savedVersion = lastSessionListVersion
        lastSessionListVersion = -1
        updateTerminals(
            selectedID: lastSelectedID,
            tmuxAvailable: lastTmuxAvailable ?? false,
            suppressInteraction: lastSuppressInteraction ?? false,
            sessionListVersion: savedVersion
        )
    }

    private func setupDiffTableView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.usesAutomaticRowHeights = false
        tableView.rowSizeStyle = .custom

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        let delegate = DiffTableDelegate()
        tableView.dataSource = delegate
        tableView.delegate = delegate
        self.diffDelegate = delegate
        self.diffScrollView = scrollView

        diffContainer.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: diffContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: diffContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: diffContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: diffContainer.bottomAnchor),
        ])

        // Empty state label
        let emptyLabel = NSTextField(labelWithString: "No changes")
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        diffContainer.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: diffContainer.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: diffContainer.centerYAnchor),
        ])
        self.diffEmptyStateView = emptyLabel

        // Observe frame changes for side-by-side mode switching
        scrollView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(diffFrameChanged),
            name: NSView.frameDidChangeNotification, object: scrollView
        )

        // Observe async diff data loads
        NotificationCenter.default.addObserver(
            self, selector: #selector(diffDataChanged),
            name: .diffDataDidChange, object: nil
        )
    }

    @objc private func diffDataChanged() {
        guard lastDetailTab == .gitDiff else { return }
        loadDiff()
    }

    @objc private func diffFrameChanged() {
        guard let delegate = diffDelegate, let scrollView = diffScrollView else { return }
        let newSideBySide = scrollView.frame.width >= 800
        guard newSideBySide != delegate.isSideBySide else { return }
        delegate.rebuildRows(for: scrollView.frame.width)
        (scrollView.documentView as? NSTableView)?.reloadData()
    }

    /// Syncs tab/diff state. Called from updateTerminals and from tab bar button actions.
    func updateTabState(selectedID: UUID?, suppressInteraction: Bool) {
        let tab = appState.currentDetailTab
        let isGitRepo = appState.folderForSelectedSession?.isGitRepo ?? false

        tabBarView.update(sessionID: selectedID, isGitRepo: isGitRepo, selectedTab: tab)
        tabBarView.isHidden = !isGitRepo
        if isGitRepo {
            contentTopToRoot.isActive = false
            contentTopToTabBar.isActive = true
        } else {
            contentTopToTabBar.isActive = false
            contentTopToRoot.isActive = true
        }

        let tabChanged = tab != lastDetailTab
        lastDetailTab = tab

        let showDiff = tab == .gitDiff
        diffContainer.isHidden = !showDiff

        // Suppress terminal interaction when diff tab is active or command palette is open
        let fullSuppress = suppressInteraction || showDiff
        for subview in terminalContainer.subviews {
            if let hubTerminal = subview as? TermHubTerminalView {
                hubTerminal.blockScrollEvents = fullSuppress
            }
        }

        // Load diff when switching to diff tab or when session changes while on diff tab
        if showDiff && (tabChanged || selectedID != lastSelectedID) {
            loadDiff()
        }

        // Manage first responder
        if !fullSuppress, let selectedID,
           let session = appState.sessions.first(where: { $0.id == selectedID }),
           let terminal = appState.terminalManager.getOrCreateTerminal(
               for: session, tmuxAvailable: lastTmuxAvailable ?? false
           ) {
            if view.window?.firstResponder !== terminal {
                view.window?.makeFirstResponder(terminal)
            }
        }
    }

    private func loadDiff() {
        guard let delegate = diffDelegate, let scrollView = diffScrollView else { return }
        let tableView = scrollView.documentView as? NSTableView

        if let diff = appState.currentDiff, !diff.files.isEmpty {
            delegate.diff = diff
            delegate.lastDiff = diff
            delegate.rebuildRows(for: scrollView.frame.width)
            tableView?.reloadData()
            diffEmptyStateView?.isHidden = true
        } else {
            delegate.diff = .empty
            delegate.rows = []
            tableView?.reloadData()
            // Show empty state only when not loading (i.e. diff was loaded but had no changes)
            let hasLoadedEmpty = appState.currentDiff != nil && !appState.isDiffLoading
            diffEmptyStateView?.isHidden = !hasLoadedEmpty
            if appState.currentDiff == nil {
                appState.loadDiffForCurrentSession()
            }
        }
    }

    func updateTerminals(
        selectedID: UUID?,
        tmuxAvailable: Bool,
        suppressInteraction: Bool = false,
        sessionListVersion: Int
    ) {
        let stateChanged = sessionListVersion != lastSessionListVersion
            || selectedID != lastSelectedID
            || tmuxAvailable != lastTmuxAvailable
            || suppressInteraction != lastSuppressInteraction
        guard stateChanged else {
            updateTabState(selectedID: selectedID, suppressInteraction: suppressInteraction)
            return
        }
        lastSessionListVersion = sessionListVersion
        lastSelectedID = selectedID
        lastTmuxAvailable = tmuxAvailable
        lastSuppressInteraction = suppressInteraction

        let sessions = appState.sessions
        let manager = appState.terminalManager

        // Remove non-selected terminals from the view hierarchy so they don't
        // participate in Auto Layout during window resize. SwiftTerm rewraps its
        // entire scrollback buffer on every frame change, so keeping N hidden
        // terminals as subviews causes N expensive rewraps per resize frame.
        let activeSessionIDs = Set(sessions.map(\.id))
        for subview in terminalContainer.subviews {
            if let terminalView = subview as? LocalProcessTerminalView {
                let sessionID = manager.sessionID(for: terminalView)
                let isSelected = sessionID == selectedID
                if !isSelected || sessionID == nil || !activeSessionIDs.contains(sessionID!) {
                    terminalView.removeFromSuperview()
                }
            }
        }

        // Only add the selected terminal to the view hierarchy
        for session in sessions where session.id == selectedID {
            guard let terminal = manager.getOrCreateTerminal(for: session, tmuxAvailable: tmuxAvailable) else {
                continue
            }
            if terminal.superview !== terminalContainer {
                terminal.translatesAutoresizingMaskIntoConstraints = false
                terminalContainer.addSubview(terminal)
                let inset: CGFloat = 6
                NSLayoutConstraint.activate([
                    terminal.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor, constant: inset),
                    terminal.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor, constant: -inset),
                    terminal.topAnchor.constraint(equalTo: terminalContainer.topAnchor, constant: inset),
                    terminal.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor, constant: -inset),
                ])

                let terminalFont = NSFont(name: "SF Mono", size: 13)
                    ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                terminal.font = terminalFont
                terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
                terminal.nativeForegroundColor = NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0)
            }

            manager.startProcessIfNeeded(for: session, tmuxAvailable: tmuxAvailable)
        }

        updateTabState(selectedID: selectedID, suppressInteraction: suppressInteraction)
    }
}

// MARK: - AppKit Tab Bar

class DetailTabBarNSView: NSView {
    private let terminalButton = NSButton()
    private let diffButton = NSButton()
    private weak var appState: AppState?
    private var sessionID: UUID?
    private var selectedTab: DetailTab = .terminal

    // Switchable constraints for single-tab vs two-tab layout
    private var terminalTrailingAlone: NSLayoutConstraint!
    private var terminalTrailingWithDiff: NSLayoutConstraint!
    private var equalWidthConstraint: NSLayoutConstraint!

    init(appState: AppState) {
        self.appState = appState
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0).cgColor

        let font = NSFont.systemFont(ofSize: 12, weight: .medium)

        configureButton(terminalButton, title: "Terminal", font: font)
        terminalButton.target = self
        terminalButton.action = #selector(terminalTapped)

        configureButton(diffButton, title: "Git Diff", font: font)
        diffButton.target = self
        diffButton.action = #selector(diffTapped)

        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        // When diff is hidden, terminal button fills the full width
        terminalTrailingAlone = terminalButton.trailingAnchor.constraint(equalTo: trailingAnchor)
        // When both tabs shown, terminal trailing connects to diff leading
        terminalTrailingWithDiff = diffButton.leadingAnchor.constraint(equalTo: terminalButton.trailingAnchor)
        equalWidthConstraint = terminalButton.widthAnchor.constraint(equalTo: diffButton.widthAnchor)

        NSLayoutConstraint.activate([
            terminalButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalButton.topAnchor.constraint(equalTo: topAnchor),
            terminalButton.bottomAnchor.constraint(equalTo: bottomAnchor),

            diffButton.topAnchor.constraint(equalTo: topAnchor),
            diffButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            diffButton.trailingAnchor.constraint(equalTo: trailingAnchor),

            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),
        ])

        // Default to two-tab layout
        terminalTrailingWithDiff.isActive = true
        equalWidthConstraint.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configureButton(_ button: NSButton, title: String, font: NSFont) {
        button.title = title
        button.font = font
        button.isBordered = false
        button.bezelStyle = .inline
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        button.wantsLayer = true
        button.layer?.cornerRadius = 0
    }

    func update(sessionID: UUID?, isGitRepo: Bool, selectedTab: DetailTab) {
        self.sessionID = sessionID
        self.selectedTab = selectedTab
        diffButton.isHidden = !isGitRepo

        // Switch constraints based on whether diff tab is visible
        if isGitRepo {
            terminalTrailingAlone.isActive = false
            terminalTrailingWithDiff.isActive = true
            equalWidthConstraint.isActive = true
        } else {
            terminalTrailingWithDiff.isActive = false
            equalWidthConstraint.isActive = false
            terminalTrailingAlone.isActive = true
        }

        let activeColor = NSColor.white.withAlphaComponent(0.10)
        let clearColor = NSColor.clear

        terminalButton.layer?.backgroundColor = (selectedTab == .terminal ? activeColor : clearColor).cgColor
        terminalButton.contentTintColor = selectedTab == .terminal ? .white : .secondaryLabelColor

        diffButton.layer?.backgroundColor = (selectedTab == .gitDiff ? activeColor : clearColor).cgColor
        diffButton.contentTintColor = selectedTab == .gitDiff ? .white : .secondaryLabelColor
    }

    @objc private func terminalTapped() {
        guard let sessionID, let appState else { return }
        appState.setDetailTab(.terminal, for: sessionID)
        if let controller = findController() {
            controller.updateTabState(selectedID: sessionID, suppressInteraction: appState.showCommandPalette)
        }
    }

    @objc private func diffTapped() {
        guard let sessionID, let appState else { return }
        appState.setDetailTab(.gitDiff, for: sessionID)
        if let controller = findController() {
            controller.updateTabState(selectedID: sessionID, suppressInteraction: appState.showCommandPalette)
        }
    }

    private func findController() -> TerminalContainerViewController? {
        var responder = self.nextResponder
        while let next = responder {
            if let controller = next as? TerminalContainerViewController {
                return controller
            }
            responder = next.nextResponder
        }
        return nil
    }
}
