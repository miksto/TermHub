import SwiftUI

@main
struct MuxManagerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Shell in Current Folder") {
                    newShellInCurrentFolder()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(appState.selectedSession == nil)

                Button("Add Folder...") {
                    appState.showingAddFolder = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Close Session") {
                    appState.pendingCloseSessionID = appState.selectedSessionID
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(appState.selectedSession == nil)
            }

            CommandGroup(after: .toolbar) {
                Button("Previous Session") {
                    appState.selectPreviousSession()
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

                Button("Next Session") {
                    appState.selectNextSession()
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }
        }
    }

    private func newShellInCurrentFolder() {
        guard let session = appState.selectedSession,
              let folder = appState.folders.first(where: { $0.id == session.folderID })
        else { return }
        appState.addSession(
            folderID: folder.id,
            title: "\(folder.name) – Shell",
            cwd: folder.path
        )
    }
}
