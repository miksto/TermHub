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
    private var wrapToggleButton: NSButton?
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

        let delegate = DiffTableDelegate()

        let tableView = SelectableDiffTableView()
        tableView.diffDelegate = delegate
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

        // Line wrap toggle button
        let wrapButton = NSButton()
        wrapButton.image = NSImage(systemSymbolName: "arrow.turn.down.left", accessibilityDescription: "Toggle line wrapping")
        wrapButton.imagePosition = .imageOnly
        wrapButton.bezelStyle = .accessoryBarAction
        wrapButton.isBordered = false
        wrapButton.wantsLayer = true
        wrapButton.layer?.cornerRadius = 4
        wrapButton.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        wrapButton.contentTintColor = .white
        wrapButton.toolTip = "Toggle line wrapping"
        wrapButton.target = self
        wrapButton.action = #selector(toggleLineWrapping)
        wrapButton.translatesAutoresizingMaskIntoConstraints = false
        diffContainer.addSubview(wrapButton)
        NSLayoutConstraint.activate([
            wrapButton.topAnchor.constraint(equalTo: diffContainer.topAnchor, constant: 3),
            wrapButton.trailingAnchor.constraint(equalTo: diffContainer.trailingAnchor, constant: -6),
            wrapButton.widthAnchor.constraint(equalToConstant: 28),
            wrapButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        self.wrapToggleButton = wrapButton

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
        let width = scrollView.frame.width
        let newSideBySide = width >= 800
        if newSideBySide != delegate.isSideBySide {
            delegate.rebuildRows(for: width)
            (scrollView.documentView as? NSTableView)?.reloadData()
        } else if delegate.lineWrapping, abs(width - delegate.lastWidth) > 1 {
            delegate.lastWidth = width
            delegate.invalidateHeightCache()
            if let tableView = scrollView.documentView as? NSTableView, delegate.rows.count > 0 {
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<delegate.rows.count))
            }
        }
    }

    @objc private func toggleLineWrapping() {
        guard let delegate = diffDelegate, let scrollView = diffScrollView,
              let tableView = scrollView.documentView as? NSTableView else { return }
        delegate.lineWrapping.toggle()
        delegate.invalidateHeightCache()

        let active = delegate.lineWrapping
        wrapToggleButton?.contentTintColor = active ? .white : .secondaryLabelColor
        wrapToggleButton?.layer?.backgroundColor = (active
            ? NSColor.controlAccentColor.withAlphaComponent(0.6)
            : NSColor.white.withAlphaComponent(0.06)).cgColor

        tableView.reloadData()
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
                    (terminalView as? TermHubTerminalView)?.isVisible = false
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

            (terminal as? TermHubTerminalView)?.isVisible = true
            let folder = appState.folders.first { $0.id == session.folderID }
            manager.startProcessIfNeeded(for: session, tmuxAvailable: tmuxAvailable, sandboxName: folder?.sandboxName)
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

class SelectableDiffTableView: NSTableView {
    weak var diffDelegate: DiffTableDelegate?
    private var autoScrollTimer: Timer?
    private var lastDragPoint: NSPoint?

    override func resetCursorRects() {
        if diffDelegate?.rows.isEmpty ?? true {
            addCursorRect(visibleRect, cursor: .arrow)
        } else {
            addCursorRect(visibleRect, cursor: .iBeam)
        }
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        guard let diffDelegate else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rowIndex = row(at: point)

        let oldSelection = diffDelegate.selection

        guard rowIndex >= 0, rowIndex < diffDelegate.rows.count, isContentRow(rowIndex) else {
            diffDelegate.selection = nil
            updateSelectionDisplay(oldSelection: oldSelection, newSelection: nil)
            return
        }

        let side = selectionSide(at: point)
        let charOff = charOffset(at: point, forRow: rowIndex, side: side)
        let pos = DiffTextPosition(row: rowIndex, charOffset: charOff)
        diffDelegate.selection = DiffSelection(side: side, anchor: pos, extent: pos)
        updateSelectionDisplay(oldSelection: oldSelection, newSelection: diffDelegate.selection)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastDragPoint = point
        updateSelectionExtent(at: point)
        handleAutoScroll(at: point)
    }

    override func mouseUp(with event: NSEvent) {
        stopAutoScroll()
        lastDragPoint = nil

        if let sel = diffDelegate?.selection, sel.anchor == sel.extent {
            let old = sel
            diffDelegate?.selection = nil
            updateSelectionDisplay(oldSelection: old, newSelection: nil)
        }
    }

    // MARK: - Copy

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
            if let text = selectedText() {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    private func selectedText() -> String? {
        guard let diffDelegate, let sel = diffDelegate.selection else { return nil }
        let start = sel.start
        let end = sel.end
        guard start < end else { return nil }

        var lines: [String] = []
        for row in start.row...end.row {
            guard let text = contentText(forRow: row, side: sel.side) else { continue }

            let startIdx = text.index(
                text.startIndex,
                offsetBy: min(row == start.row ? start.charOffset : 0, text.count)
            )
            let endIdx = text.index(
                text.startIndex,
                offsetBy: min(row == end.row ? end.charOffset : text.count, text.count)
            )

            guard startIdx < endIdx else { continue }
            lines.append(String(text[startIdx..<endIdx]))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // MARK: - Selection Helpers

    private func selectionSide(at point: NSPoint) -> DiffSelectionSide {
        guard let diffDelegate, diffDelegate.isSideBySide else { return .unified }
        let half = floor(bounds.width / 2)
        return point.x < half ? .left : .right
    }

    private func isContentRow(_ row: Int) -> Bool {
        guard let diffDelegate, row >= 0, row < diffDelegate.rows.count else { return false }
        switch diffDelegate.rows[row].kind {
        case .unifiedLine, .sideBySideLine: return true
        default: return false
        }
    }

    private func contentText(forRow row: Int, side: DiffSelectionSide) -> String? {
        guard let diffDelegate, row >= 0, row < diffDelegate.rows.count else { return nil }
        switch diffDelegate.rows[row].kind {
        case .unifiedLine(let line):
            return line.content
        case .sideBySideLine(let old, let new):
            switch side {
            case .left: return old?.content
            case .right: return new?.content
            case .unified: return nil
            }
        default:
            return nil
        }
    }

    private func charOffset(at point: NSPoint, forRow rowIndex: Int, side: DiffSelectionSide) -> Int {
        guard let diffDelegate else { return 0 }
        let rowRect = rect(ofRow: rowIndex)
        let localY = point.y - rowRect.minY
        let gw = DiffMetrics.gutterWidth
        let pw = DiffMetrics.prefixWidth

        let contentStartX: CGFloat
        let contentWidth: CGFloat

        switch side {
        case .unified:
            contentStartX = gw * 2 + pw
            contentWidth = bounds.width - contentStartX - 4
        case .left:
            contentStartX = gw + pw
            let half = floor(bounds.width / 2)
            contentWidth = half - gw - pw - 4
        case .right:
            let half = floor(bounds.width / 2)
            contentStartX = half + 1 + gw + pw
            contentWidth = bounds.width - half - 1 - gw - pw - 4
        }

        let relativeX = point.x - contentStartX
        let text = contentText(forRow: rowIndex, side: side) ?? ""

        if !diffDelegate.lineWrapping || text.isEmpty {
            let offset = Int(floor(relativeX / DiffFonts.monoCharWidth))
            return max(0, min(offset, text.count))
        } else {
            let storage = NSTextStorage(string: text, attributes: [.font: DiffFonts.mono])
            let layoutManager = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)
            layoutManager.ensureLayout(for: container)

            let hitPoint = NSPoint(x: max(0, relativeX), y: max(0, localY - 2))
            let index = layoutManager.characterIndex(
                for: hitPoint, in: container,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            return max(0, min(index, text.count))
        }
    }

    private func updateSelectionExtent(at point: NSPoint) {
        guard let diffDelegate, var sel = diffDelegate.selection else { return }
        let oldSelection = sel

        var rowIndex = row(at: point)
        if rowIndex < 0 {
            rowIndex = 0
        } else if rowIndex >= diffDelegate.rows.count {
            rowIndex = diffDelegate.rows.count - 1
        }

        // Find nearest content row
        if !isContentRow(rowIndex) {
            let goingDown = rowIndex >= sel.anchor.row
            if goingDown {
                var r = rowIndex
                while r < diffDelegate.rows.count && !isContentRow(r) { r += 1 }
                if r >= diffDelegate.rows.count {
                    r = rowIndex
                    while r >= 0 && !isContentRow(r) { r -= 1 }
                }
                rowIndex = max(0, r)
            } else {
                var r = rowIndex
                while r >= 0 && !isContentRow(r) { r -= 1 }
                if r < 0 {
                    r = rowIndex
                    while r < diffDelegate.rows.count && !isContentRow(r) { r += 1 }
                }
                rowIndex = min(diffDelegate.rows.count - 1, r)
            }
        }

        guard isContentRow(rowIndex) else { return }
        let charOff = charOffset(at: point, forRow: rowIndex, side: sel.side)
        sel.extent = DiffTextPosition(row: rowIndex, charOffset: charOff)
        diffDelegate.selection = sel
        updateSelectionDisplay(oldSelection: oldSelection, newSelection: sel)
    }

    private func updateSelectionDisplay(oldSelection: DiffSelection?, newSelection: DiffSelection?) {
        guard let diffDelegate else { return }

        var minRow = Int.max
        var maxRow = -1
        if let old = oldSelection {
            minRow = min(minRow, old.start.row)
            maxRow = max(maxRow, old.end.row)
        }
        if let new = newSelection {
            minRow = min(minRow, new.start.row)
            maxRow = max(maxRow, new.end.row)
        }
        guard minRow <= maxRow else { return }

        let visibleRange = rows(in: visibleRect)
        let visEnd = visibleRange.location + visibleRange.length
        for r in max(minRow, visibleRange.location)..<min(maxRow + 1, visEnd) {
            guard let cellView = view(atColumn: 0, row: r, makeIfNecessary: false) else { continue }
            let selRange = diffDelegate.selectionRange(forRow: r)

            if let unified = cellView as? UnifiedLineDrawView {
                unified.selectionStartChar = selRange?.start
                unified.selectionEndChar = selRange?.end
                unified.needsDisplay = true
            } else if let sbs = cellView as? SideBySideLineDrawView {
                sbs.selectionSide = newSelection?.side
                sbs.selectionStartChar = selRange?.start
                sbs.selectionEndChar = selRange?.end
                sbs.needsDisplay = true
            }
        }
    }

    // MARK: - Auto-scroll

    private func handleAutoScroll(at point: NSPoint) {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let visibleRect = clipView.bounds
        let localY = convert(point, to: clipView).y

        if localY < visibleRect.minY + 30 || localY > visibleRect.maxY - 30 {
            if autoScrollTimer == nil {
                autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.performAutoScroll()
                    }
                }
            }
        } else {
            stopAutoScroll()
        }
    }

    private func performAutoScroll() {
        guard let scrollView = enclosingScrollView,
              let window else { return }
        let clipView = scrollView.contentView
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInClip = clipView.convert(mouseInWindow, from: nil)
        let visibleRect = clipView.bounds

        let scrollAmount: CGFloat
        if mouseInClip.y < visibleRect.minY + 30 {
            scrollAmount = -20
        } else if mouseInClip.y > visibleRect.maxY - 30 {
            scrollAmount = 20
        } else {
            stopAutoScroll()
            return
        }

        var origin = visibleRect.origin
        origin.y += scrollAmount
        origin.y = max(0, min(origin.y, frame.height - visibleRect.height))
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)

        let mouseInTable = convert(mouseInWindow, from: nil)
        updateSelectionExtent(at: mouseInTable)
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
}

