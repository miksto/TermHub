import SwiftUI
import SwiftTerm

struct TerminalNSViewWrapper: NSViewRepresentable {
    @Environment(AppState.self) private var appState
    let session: TerminalSession

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = appState.terminalManager.getOrCreateTerminal(
            for: session,
            tmuxAvailable: appState.tmuxAvailable
        )

        // Configure terminal appearance
        let terminalFont: NSFont = NSFont(name: "SF Mono", size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let terminalView = terminal.getTerminal()
        terminal.font = terminalFont
        terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        terminal.nativeForegroundColor = NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0)

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No dynamic updates needed for now
    }
}
