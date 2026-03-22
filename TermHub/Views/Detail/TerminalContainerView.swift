import SwiftUI
import SwiftTerm

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
    private let containerView = NSView()
    private let appState: AppState
    private var lastSessionListVersion = -1
    private var lastSelectedID: UUID?
    private var lastTmuxAvailable: Bool?
    private var lastSuppressInteraction: Bool?

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).cgColor
        self.view = containerView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Re-run with last known state now that we're in the window hierarchy.
        // Reset version so the guard in updateTerminals allows it through.
        let savedVersion = lastSessionListVersion
        lastSessionListVersion = -1
        updateTerminals(
            selectedID: lastSelectedID,
            tmuxAvailable: lastTmuxAvailable ?? false,
            suppressInteraction: lastSuppressInteraction ?? false,
            sessionListVersion: savedVersion
        )
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
        guard stateChanged else { return }
        lastSessionListVersion = sessionListVersion
        lastSelectedID = selectedID
        lastTmuxAvailable = tmuxAvailable
        lastSuppressInteraction = suppressInteraction

        // Read sessions from appState directly (not through SwiftUI observation).
        let sessions = appState.sessions
        let manager = appState.terminalManager

        for session in sessions {
            guard let terminal = manager.getOrCreateTerminal(for: session, tmuxAvailable: tmuxAvailable) else {
                continue
            }
            if terminal.superview !== containerView {
                terminal.translatesAutoresizingMaskIntoConstraints = false
                containerView.addSubview(terminal)
                let inset: CGFloat = 6
                NSLayoutConstraint.activate([
                    terminal.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: inset),
                    terminal.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -inset),
                    terminal.topAnchor.constraint(equalTo: containerView.topAnchor, constant: inset),
                    terminal.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -inset),
                ])

                let terminalFont = NSFont(name: "SF Mono", size: 13)
                    ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                terminal.font = terminalFont
                terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
                terminal.nativeForegroundColor = NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0)
            }

            // Block scroll events on the terminal when the palette is open
            if let hubTerminal = terminal as? TermHubTerminalView {
                hubTerminal.blockScrollEvents = suppressInteraction
            }

            let isSelected = session.id == selectedID
            let shouldHide = !isSelected
            if terminal.isHidden != shouldHide {
                terminal.isHidden = shouldHide
            }
            if isSelected {
                manager.startProcessIfNeeded(for: session, tmuxAvailable: tmuxAvailable)
                if !suppressInteraction, view.window?.firstResponder !== terminal {
                    view.window?.makeFirstResponder(terminal)
                }
            }
        }

        let activeSessionIDs = Set(sessions.map(\.id))
        for subview in containerView.subviews {
            if let terminalView = subview as? LocalProcessTerminalView {
                let sessionID = manager.sessionID(for: terminalView)
                if sessionID == nil || !activeSessionIDs.contains(sessionID!) {
                    terminalView.removeFromSuperview()
                }
            }
        }
    }
}
