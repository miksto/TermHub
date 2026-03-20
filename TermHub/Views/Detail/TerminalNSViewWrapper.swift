import SwiftUI
import SwiftTerm

struct TerminalNSViewWrapper: NSViewRepresentable {
    @Environment(AppState.self) private var appState
    let session: TerminalSession

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = appState.terminalManager.getOrCreateTerminal(
            for: session,
            tmuxAvailable: appState.tmuxAvailable
        )

        // Configure terminal appearance
        let terminalFont: NSFont = NSFont(name: "SF Mono", size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.font = terminalFont
        terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        terminal.nativeForegroundColor = NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0)

        terminal.processDelegate = context.coordinator

        // Defer process start until after the view is in the window hierarchy
        let manager = appState.terminalManager
        let sessionCopy = session
        let tmuxAvailable = appState.tmuxAvailable
        DispatchQueue.main.async {
            manager.startProcessIfNeeded(for: sessionCopy, tmuxAvailable: tmuxAvailable)
        }

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Start process if it hasn't been started yet (e.g., after view re-appears)
        let manager = appState.terminalManager
        let sessionCopy = session
        let tmuxAvailable = appState.tmuxAvailable
        DispatchQueue.main.async {
            manager.startProcessIfNeeded(for: sessionCopy, tmuxAvailable: tmuxAvailable)
        }
    }

    final class Coordinator: LocalProcessTerminalViewDelegate {
        nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}
