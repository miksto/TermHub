import Foundation
import Observation

enum FolderAction: Sendable {
    case newShell
    case newShellFromBranch
    case newShellNewBranch
    case removeFolder
}

enum TextInputAction: Sendable {
    case renameSession(sessionID: UUID)
    case newBranch(folder: ManagedFolder)
}

enum PaletteMode: Sendable {
    case commands
    case sessionPicker
    case folderPicker(action: FolderAction)
    case branchPicker(folder: ManagedFolder)
    case textInput(prompt: String, action: TextInputAction)
}

struct PaletteItem: Identifiable, Sendable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let category: String?
    let action: @MainActor @Sendable () -> Void

    init(
        id: String,
        icon: String,
        title: String,
        subtitle: String? = nil,
        category: String? = nil,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.action = action
    }
}

@Observable
@MainActor
final class CommandPaletteState {
    var query: String = ""
    var selectedIndex: Int = 0
    var modeStack: [PaletteMode] = [.commands]
    var branches: [String] = []
    var isLoadingBranches: Bool = false
    var branchLoadError: String?

    var currentMode: PaletteMode {
        modeStack.last ?? .commands
    }

    var breadcrumbs: [String] {
        modeStack.compactMap { mode in
            switch mode {
            case .commands: return nil
            case .sessionPicker: return "Go to Session"
            case .folderPicker(let action):
                switch action {
                case .newShell: return "New Shell"
                case .newShellFromBranch: return "Branch Session"
                case .newShellNewBranch: return "New Branch"
                case .removeFolder: return "Remove Folder"
                }
            case .branchPicker(let folder): return folder.name
            case .textInput(let prompt, _): return prompt
            }
        }
    }

    func pushMode(_ mode: PaletteMode) {
        modeStack.append(mode)
        query = ""
        selectedIndex = 0
    }

    /// Returns `true` if a mode was popped, `false` if the stack is at root (should dismiss).
    func popMode() -> Bool {
        guard modeStack.count > 1 else { return false }
        modeStack.removeLast()
        query = ""
        selectedIndex = 0
        return true
    }

    func moveSelectionUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func moveSelectionDown(itemCount: Int) {
        if selectedIndex < itemCount - 1 {
            selectedIndex += 1
        }
    }

    func clampSelection(itemCount: Int) {
        if itemCount == 0 {
            selectedIndex = 0
        } else if selectedIndex >= itemCount {
            selectedIndex = itemCount - 1
        }
    }

    func reset() {
        query = ""
        selectedIndex = 0
        modeStack = [.commands]
        branches = []
        isLoadingBranches = false
        branchLoadError = nil
    }

    func items(appState: AppState, dismiss: @escaping @MainActor @Sendable () -> Void) -> [PaletteItem] {
        switch currentMode {
        case .commands:
            return commandItems(appState: appState, dismiss: dismiss)
        case .sessionPicker:
            return sessionPickerItems(appState: appState, dismiss: dismiss)
        case .folderPicker(let action):
            return folderPickerItems(appState: appState, action: action, dismiss: dismiss)
        case .branchPicker(let folder):
            return branchPickerItems(folder: folder, appState: appState, dismiss: dismiss)
        case .textInput:
            return []
        }
    }

    // MARK: - Item Builders

    private func commandItems(appState: AppState, dismiss: @escaping @MainActor @Sendable () -> Void) -> [PaletteItem] {
        let items = buildActionItems(appState: appState, dismiss: dismiss)
        return filterByQuery(items)
    }

    private func sessionPickerItems(appState: AppState, dismiss: @escaping @MainActor @Sendable () -> Void) -> [PaletteItem] {
        let items = appState.sessions.map { session in
            let folder = appState.folders.first { $0.id == session.folderID }
            let subtitle = [folder?.name, session.branchName].compactMap { $0 }.joined(separator: " / ")
            return PaletteItem(
                id: "session-\(session.id.uuidString)",
                icon: "terminal",
                title: session.title,
                subtitle: subtitle.isEmpty ? nil : subtitle
            ) { [weak appState] in
                appState?.selectedSessionID = session.id
                dismiss()
            }
        }
        return filterByQuery(items)
    }

    private func buildActionItems(appState: AppState, dismiss: @escaping @MainActor @Sendable () -> Void) -> [PaletteItem] {
        var actions: [PaletteItem] = []

        // Go to Session
        if !appState.sessions.isEmpty {
            actions.append(PaletteItem(
                id: "action-go-to-session",
                icon: "terminal",
                title: "Go to Session",
                category: "Actions"
            ) { [weak self] in
                self?.pushMode(.sessionPicker)
            })
        }

        // New Shell
        if appState.folders.count == 1 {
            let folder = appState.folders[0]
            actions.append(PaletteItem(
                id: "action-new-shell",
                icon: "plus.rectangle",
                title: "New Shell",
                subtitle: folder.name,
                category: "Actions"
            ) { [weak appState] in
                appState?.addSession(folderID: folder.id, title: "\(folder.name) – Shell", cwd: folder.path)
                dismiss()
            })
        } else if appState.folders.count > 1 {
            actions.append(PaletteItem(
                id: "action-new-shell",
                icon: "plus.rectangle",
                title: "New Shell",
                category: "Actions"
            ) { [weak self] in
                self?.pushMode(.folderPicker(action: .newShell))
            })
        }

        // New Shell from Branch
        let gitFolders = appState.folders.filter(\.isGitRepo)
        if gitFolders.count == 1 {
            let folder = gitFolders[0]
            actions.append(PaletteItem(
                id: "action-new-shell-from-branch",
                icon: "arrow.triangle.branch",
                title: "New Shell from Branch",
                subtitle: folder.name,
                category: "Actions"
            ) { [weak self] in
                self?.loadBranchesAndPush(folder: folder)
            })
        } else if gitFolders.count > 1 {
            actions.append(PaletteItem(
                id: "action-new-shell-from-branch",
                icon: "arrow.triangle.branch",
                title: "New Shell from Branch",
                category: "Actions"
            ) { [weak self] in
                self?.pushMode(.folderPicker(action: .newShellFromBranch))
            })
        }

        // New Shell with New Branch
        if gitFolders.count == 1 {
            let folder = gitFolders[0]
            actions.append(PaletteItem(
                id: "action-new-shell-new-branch",
                icon: "plus.diamond",
                title: "New Shell with New Branch",
                subtitle: folder.name,
                category: "Actions"
            ) { [weak self] in
                self?.pushMode(.textInput(prompt: "Branch name", action: .newBranch(folder: folder)))
            })
        } else if gitFolders.count > 1 {
            actions.append(PaletteItem(
                id: "action-new-shell-new-branch",
                icon: "plus.diamond",
                title: "New Shell with New Branch",
                category: "Actions"
            ) { [weak self] in
                self?.pushMode(.folderPicker(action: .newShellNewBranch))
            })
        }

        // Close Current Session
        if appState.selectedSession != nil {
            actions.append(PaletteItem(
                id: "action-close-session",
                icon: "xmark.rectangle",
                title: "Close Current Session",
                category: "Actions"
            ) { [weak appState] in
                if let id = appState?.selectedSessionID {
                    appState?.removeSession(id: id)
                }
                dismiss()
            })
        }

        // Rename Current Session
        if let session = appState.selectedSession {
            actions.append(PaletteItem(
                id: "action-rename-session",
                icon: "pencil",
                title: "Rename Current Session",
                category: "Actions"
            ) { [weak self] in
                self?.pushMode(.textInput(prompt: "Session name", action: .renameSession(sessionID: session.id)))
            })
        }

        // Add Folder
        actions.append(PaletteItem(
            id: "action-add-folder",
            icon: "folder.badge.plus",
            title: "Add Folder",
            category: "Actions"
        ) { [weak appState] in
            dismiss()
            appState?.showAddFolderPanel()
        })

        // Remove Folder
        if appState.folders.count == 1 {
            let folder = appState.folders[0]
            actions.append(PaletteItem(
                id: "action-remove-folder",
                icon: "folder.badge.minus",
                title: "Remove Folder",
                subtitle: folder.name,
                category: "Actions"
            ) { [weak appState] in
                dismiss()
                appState?.pendingRemoveFolderID = folder.id
            })
        } else if appState.folders.count > 1 {
            actions.append(PaletteItem(
                id: "action-remove-folder",
                icon: "folder.badge.minus",
                title: "Remove Folder",
                category: "Actions"
            ) { [weak self] in
                self?.pushMode(.folderPicker(action: .removeFolder))
            })
        }

        // Show Keyboard Shortcuts
        actions.append(PaletteItem(
            id: "action-keyboard-shortcuts",
            icon: "keyboard",
            title: "Show Keyboard Shortcuts",
            category: "Actions"
        ) { [weak appState] in
            appState?.showKeyboardShortcuts = true
            dismiss()
        })

        return actions
    }

    private func folderPickerItems(
        appState: AppState,
        action: FolderAction,
        dismiss: @escaping @MainActor @Sendable () -> Void
    ) -> [PaletteItem] {
        let folders: [ManagedFolder]
        switch action {
        case .newShellFromBranch, .newShellNewBranch:
            folders = appState.folders.filter(\.isGitRepo)
        default:
            folders = appState.folders
        }

        let items = folders.map { folder in
            PaletteItem(
                id: "folder-\(folder.id.uuidString)",
                icon: "folder",
                title: folder.name,
                subtitle: folder.path
            ) { [weak self, weak appState] in
                guard let self, let appState else { return }
                switch action {
                case .newShell:
                    appState.addSession(folderID: folder.id, title: "\(folder.name) – Shell", cwd: folder.path)
                    dismiss()
                case .newShellFromBranch:
                    self.loadBranchesAndPush(folder: folder)
                case .newShellNewBranch:
                    self.pushMode(.textInput(prompt: "Branch name", action: .newBranch(folder: folder)))
                case .removeFolder:
                    dismiss()
                    appState.pendingRemoveFolderID = folder.id
                }
            }
        }

        return filterByQuery(items)
    }

    private func branchPickerItems(
        folder: ManagedFolder,
        appState: AppState,
        dismiss: @escaping @MainActor @Sendable () -> Void
    ) -> [PaletteItem] {
        let items = branches.map { branch in
            PaletteItem(
                id: "branch-\(branch)",
                icon: "arrow.triangle.branch",
                title: branch
            ) { [weak appState] in
                do {
                    let worktreePath = try GitService.addWorktree(repoPath: folder.path, branch: branch)
                    appState?.addSession(
                        folderID: folder.id,
                        title: "\(folder.name) / \(branch)",
                        cwd: worktreePath,
                        worktreePath: worktreePath,
                        branchName: branch
                    )
                } catch {
                    appState?.errorMessage = error.localizedDescription
                }
                dismiss()
            }
        }

        return filterByQuery(items)
    }

    private func filterByQuery(_ items: [PaletteItem]) -> [PaletteItem] {
        guard !query.isEmpty else { return items }
        return items.compactMap { item in
            let searchText = [item.title, item.subtitle].compactMap { $0 }.joined(separator: " ")
            if let score = FuzzyMatch.score(query: query, candidate: searchText) {
                return (item, score)
            }
            return nil
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    func loadBranchesAndPush(folder: ManagedFolder) {
        isLoadingBranches = true
        branchLoadError = nil
        pushMode(.branchPicker(folder: folder))

        Task.detached { [weak self] in
            do {
                let branchList = try GitService.listBranches(repoPath: folder.path)
                await MainActor.run { [weak self] in
                    self?.branches = branchList
                    self?.isLoadingBranches = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.branchLoadError = error.localizedDescription
                    self?.isLoadingBranches = false
                }
            }
        }
    }
}
