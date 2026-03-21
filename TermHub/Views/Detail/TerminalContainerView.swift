import SwiftUI
import SwiftTerm

/// Uses NSViewControllerRepresentable instead of NSViewRepresentable to get
/// proper mouse event delivery. NSViewRepresentable can intercept mouse events
/// before they reach the embedded NSView.
struct TerminalContainerView: NSViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    let selectedSessionID: UUID?

    func makeNSViewController(context: Context) -> TerminalContainerViewController {
        TerminalContainerViewController()
    }

    func updateNSViewController(_ controller: TerminalContainerViewController, context: Context) {
        let manager = appState.terminalManager
        let tmuxAvailable = appState.tmuxAvailable
        let sessions = appState.sessions
        let selectedID = selectedSessionID
        let suppressInteraction = appState.showCommandPalette

        DispatchQueue.main.async {
            controller.updateTerminals(
                sessions: sessions,
                selectedID: selectedID,
                manager: manager,
                tmuxAvailable: tmuxAvailable,
                suppressInteraction: suppressInteraction
            )
        }
    }
}

class TerminalContainerViewController: NSViewController {
    private let containerView = NSView()

    override func loadView() {
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).cgColor
        self.view = containerView
    }

    func updateTerminals(
        sessions: [TerminalSession],
        selectedID: UUID?,
        manager: TerminalSessionManager,
        tmuxAvailable: Bool,
        suppressInteraction: Bool = false
    ) {
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
            terminal.isHidden = !isSelected
            if isSelected {
                manager.startProcessIfNeeded(for: session, tmuxAvailable: tmuxAvailable)
                if !suppressInteraction {
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
