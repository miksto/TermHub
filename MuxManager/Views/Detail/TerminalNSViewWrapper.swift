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
        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No dynamic updates needed for now
    }
}
