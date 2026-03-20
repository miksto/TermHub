import SwiftUI
import SwiftTerm

/// A container NSView that holds all terminal views as subviews,
/// showing only the selected one. This avoids SwiftUI's NSViewRepresentable
/// lifecycle issues (destroy/recreate) when switching between sessions.
struct TerminalContainerView: NSViewRepresentable {
    @Environment(AppState.self) private var appState
    let selectedSessionID: UUID?

    func makeNSView(context: Context) -> MousePassthroughView {
        let container = MousePassthroughView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).cgColor
        return container
    }

    func updateNSView(_ container: MousePassthroughView, context: Context) {
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
                    let inset: CGFloat = 6
                    NSLayoutConstraint.activate([
                        terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
                        terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
                        terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
                        terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
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

/// Container NSView that ensures mouse events reach the terminal subviews.
/// Clicks on the container itself (the padding area) are forwarded to the
/// visible terminal and it becomes first responder.
class MousePassthroughView: NSView {
    override func mouseDown(with event: NSEvent) {
        if let terminal = visibleTerminal() {
            window?.makeFirstResponder(terminal)
            terminal.mouseDown(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { false }

    private func visibleTerminal() -> NSView? {
        subviews.first { !$0.isHidden }
    }
}
