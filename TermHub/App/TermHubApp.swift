import SwiftUI

@main
struct TermHubApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onOpenURL { url in
                    handleURL(url)
                }
                .handlesExternalEvents(preferring: Set(arrayLiteral: "*"), allowing: Set(arrayLiteral: "*"))
        }
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Folder...") {
                    appState.showAddFolderPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("New Shell in Current Folder") {
                    newShellInCurrentFolder()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(appState.selectedSession == nil)

                Button("New Sandbox Shell in Current Folder") {
                    newShellInCurrentFolder(sandbox: true)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(appState.selectedSession == nil || appState.folderForSelectedSession?.hasSandbox != true)
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
                .keyboardShortcut("/", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Command Palette") {
                    appState.showCommandPalette.toggle()
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Switch Branch / Worktree…") {
                    if let session = appState.selectedSession,
                       let folder = appState.folders.first(where: { $0.id == session.folderID }) {
                        appState.pendingWorktreeFolder = folder
                    }
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(appState.selectedSession == nil)

                Button("New Worktree…") {
                    if let session = appState.selectedSession,
                       let folder = appState.folders.first(where: { $0.id == session.folderID }) {
                        appState.pendingNewBranchFolder = folder
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.selectedSession == nil)

                Button("Toggle Git Diff") {
                    appState.toggleDetailTab()
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(appState.selectedSession == nil)

                Button("Previous Tab") {
                    appState.selectPreviousDetailTab()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(appState.selectedSession == nil)

                Button("Next Tab") {
                    appState.selectNextDetailTab()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(appState.selectedSession == nil)

                Button("Previous Session") {
                    appState.selectPreviousSession()
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

                Button("Next Session") {
                    appState.selectNextSession()
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

                Button("Jump to Notification") {
                    appState.selectNextSessionNeedingAttention()
                }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(appState.sessionsNeedingAttention.isEmpty)

                ForEach(1...9, id: \.self) { number in
                    Button("Session \(number)") {
                        appState.selectSessionByIndex(number - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
            }
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "termhub", url.host == "new-worktree" else {
            print("[TermHub] Unknown URL: \(url)")
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = components?.queryItems?.reduce(into: [String: String]()) {
            $0[$1.name] = $1.value
        } ?? [:]

        guard let repoPath = params["repo"] else {
            appState.errorMessage = "Missing 'repo' parameter in URL"
            return
        }
        guard let branch = params["branch"] else {
            appState.errorMessage = "Missing 'branch' parameter in URL"
            return
        }

        guard let folder = appState.folders.first(where: { $0.path == repoPath }) else {
            appState.errorMessage = "Repo not found in managed folders: \(repoPath)"
            return
        }

        let folderID = folder.id
        let folderName = folder.name
        let plan = params["plan"]

        Task.detached {
            do {
                let worktreePath = try GitService.addWorktreeNewBranch(repoPath: repoPath, newBranch: branch)
                await MainActor.run { [weak appState] in
                    guard let appState else { return }
                    let title = "\(folderName) [\(branch)]"
                    appState.addSession(
                        folderID: folderID,
                        title: title,
                        cwd: worktreePath,
                        worktreePath: worktreePath,
                        branchName: branch,
                        ownsBranch: true
                    )
                    if let plan, let sessionID = appState.selectedSessionID {
                        let command = "claude \"Implement the plan in \(plan)\""
                        appState.terminalManager.pendingCommands[sessionID] = command
                    }
                }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { [weak appState] in
                    appState?.errorMessage = "Failed to create worktree: \(msg)"
                }
            }
        }
    }

    private func newShellInCurrentFolder(sandbox: Bool = false) {
        guard let session = appState.selectedSession,
              let folder = appState.folders.first(where: { $0.id == session.folderID })
        else { return }

        let useSandbox = sandbox && folder.hasSandbox

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
            branchName: session.branchName,
            isSandboxSession: useSandbox
        )
    }
}
