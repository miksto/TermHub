import SwiftUI
import SwiftTerm

/// A container NSView that holds all terminal views as subviews,
/// showing only the selected one. This avoids SwiftUI's NSViewRepresentable
/// lifecycle issues (destroy/recreate) when switching between sessions.
struct TerminalContainerView: NSViewRepresentable {
    @Environment(AppState.self) private var appState
    let selectedSessionID: UUID?

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // Capture all state we need — do NOT access appState inside the async block
        let manager = appState.terminalManager
        let tmuxAvailable = appState.tmuxAvailable
        let sessions = appState.sessions
        let selectedID = selectedSessionID

        // Defer all view hierarchy changes to after SwiftUI's layout pass completes.
        // Modifying subviews during updateNSView triggers re-entrant layout and crashes.
        DispatchQueue.main.async {
            // Ensure all sessions have terminal views created and added to the container
            for session in sessions {
                let terminal = manager.getOrCreateTerminal(for: session, tmuxAvailable: tmuxAvailable)
                if terminal.superview !== container {
                    terminal.translatesAutoresizingMaskIntoConstraints = false
                    container.addSubview(terminal)
                    NSLayoutConstraint.activate([
                        terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                        terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                        terminal.topAnchor.constraint(equalTo: container.topAnchor),
                        terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    ])

                    // Configure appearance
                    let terminalFont = NSFont(name: "SF Mono", size: 13)
                        ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                    terminal.font = terminalFont
                    terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
                    terminal.nativeForegroundColor = NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0)
                }

                // Show only the selected session's terminal
                let isSelected = session.id == selectedID
                terminal.isHidden = !isSelected
                if isSelected {
                    manager.startProcessIfNeeded(for: session, tmuxAvailable: tmuxAvailable)
                    container.window?.makeFirstResponder(terminal)
                }
            }

            // Remove terminal views for sessions that no longer exist
            let activeSessionIDs = Set(sessions.map(\.id))
            for subview in container.subviews {
                if let terminalView = subview as? LocalProcessTerminalView,
                   let sessionID = manager.sessionID(for: terminalView),
                   !activeSessionIDs.contains(sessionID) {
                    terminalView.removeFromSuperview()
                }
            }
        }
    }
}
