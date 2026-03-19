import SwiftUI
import SwiftTerm

struct TerminalNSViewWrapper: NSViewRepresentable {
    @Environment(AppState.self) private var appState
    let session: TerminalSession

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState, sessionID: session.id)
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

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        context.coordinator.appState = appState
        context.coordinator.sessionID = session.id
    }

    final class Coordinator: LocalProcessTerminalViewDelegate {
        var appState: AppState
        var sessionID: UUID

        init(appState: AppState, sessionID: UUID) {
            self.appState = appState
            self.sessionID = sessionID
        }

        nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            let appState = self.appState
            let sessionID = self.sessionID
            Task { @MainActor in
                appState.renameSession(id: sessionID, newTitle: title)
            }
        }

        nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}
