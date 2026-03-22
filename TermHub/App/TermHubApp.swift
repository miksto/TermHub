import SwiftUI

@main
struct TermHubApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Shell in Current Folder") {
                    newShellInCurrentFolder()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(appState.selectedSession == nil)

                Button("Add Folder...") {
                    openFolderPanel()
                }
                .keyboardShortcut("n", modifiers: .command)

            }

            CommandGroup(replacing: .saveItem) {
                Button("Close Session") {
                    if let id = appState.selectedSessionID {
                        appState.removeSession(id: id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(appState.selectedSession == nil)
            }

            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") {
                    appState.showKeyboardShortcuts = true
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button("Command Palette") {
                    appState.showCommandPalette.toggle()
                }
                .keyboardShortcut("p", modifiers: .command)


                Button("Previous Session") {
                    appState.selectPreviousSession()
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

                Button("Next Session") {
                    appState.selectNextSession()
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

                ForEach(1...9, id: \.self) { number in
                    Button("Session \(number)") {
                        appState.selectSessionByIndex(number - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
            }
        }
    }

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.addFolder(path: url.path)
        }
    }

    private func newShellInCurrentFolder() {
        guard let session = appState.selectedSession,
              let folder = appState.folders.first(where: { $0.id == session.folderID })
        else { return }

        let title: String
        let cwd: String
        if let worktreePath = session.worktreePath {
            title = "\(folder.name) [\(session.branchName ?? "worktree")]"
            cwd = worktreePath
        } else {
            title = "\(folder.name) – Shell"
            cwd = folder.path
        }

        appState.addSession(
            folderID: folder.id,
            title: title,
            cwd: cwd,
            worktreePath: session.worktreePath,
            branchName: session.branchName
        )
    }
}
