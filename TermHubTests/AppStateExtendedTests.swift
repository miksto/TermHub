import Foundation
import Testing
@testable import TermHub

@Suite("AppState Extended Tests")
struct AppStateExtendedTests {
    private let mock = MockCommandRunner()

    init() {
        GitService.commandRunner = mock
    }

    @MainActor
    private func makeCleanAppState() -> AppState {
        AppState(persistence: NullPersistence())
    }

    // MARK: - Session Switcher (MRU)

    @Test("beginSessionSwitcher requires at least 2 sessions")
    @MainActor
    func beginSwitcherNeedsTwo() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")

        state.beginSessionSwitcher()
        #expect(state.isSessionSwitcherActive == false)
    }

    @Test("beginSessionSwitcher activates with 2+ sessions")
    @MainActor
    func beginSwitcherActivates() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")

        state.beginSessionSwitcher()
        #expect(state.isSessionSwitcherActive == true)
        #expect(state.switcherSelectedIndex == 1)
    }

    @Test("advanceSessionSwitcher wraps around")
    @MainActor
    func advanceSwitcherWraps() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")

        state.beginSessionSwitcher()
        let items = state.sessionSwitcherItems
        state.switcherSelectedIndex = items.count - 1

        state.advanceSessionSwitcher()
        #expect(state.switcherSelectedIndex == 0)
    }

    @Test("reverseSessionSwitcher wraps around")
    @MainActor
    func reverseSwitcherWraps() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")

        state.beginSessionSwitcher()
        state.switcherSelectedIndex = 0

        state.reverseSessionSwitcher()
        #expect(state.switcherSelectedIndex == state.sessionSwitcherItems.count - 1)
    }

    @Test("commitSessionSwitcher selects the session at index")
    @MainActor
    func commitSwitcherSelects() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")

        state.beginSessionSwitcher()
        let items = state.sessionSwitcherItems
        state.switcherSelectedIndex = 1

        state.commitSessionSwitcher()
        #expect(state.isSessionSwitcherActive == false)
        #expect(state.selectedSessionID == items[1].id)
    }

    @Test("commitSessionSwitcher reveals the selected session when enabled")
    @MainActor
    func commitSwitcherRevealsWhenEnabled() {
        let state = makeCleanAppState()
        defer {
            UserDefaults.standard.removeObject(forKey: "revealSelectedSessionInSidebarOnCtrlTab")
        }
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")

        state.beginSessionSwitcher()
        state.commitSessionSwitcher()

        #expect(state.selectedSessionID == state.sessions[0].id)
        #expect(state.sidebarRevealSessionID == state.sessions[0].id)
    }

    @Test("commitSessionSwitcher does not reveal the selected session when disabled")
    @MainActor
    func commitSwitcherDoesNotRevealWhenDisabled() {
        let state = makeCleanAppState()
        defer {
            UserDefaults.standard.removeObject(forKey: "revealSelectedSessionInSidebarOnCtrlTab")
        }
        state.revealSelectedSessionInSidebarOnCtrlTab = false
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")

        state.beginSessionSwitcher()
        state.commitSessionSwitcher()

        #expect(state.selectedSessionID == state.sessions[0].id)
        #expect(state.sidebarRevealSessionID == nil)
    }

    @Test("sessionSwitcherItems returns sessions in MRU order")
    @MainActor
    func switcherItemsMRUOrder() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let firstSessionID = state.sessions[0].id

        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let secondSessionID = state.sessions[1].id

        // addSession selects Shell 2, making it MRU[0]
        // Select first session to make it MRU[0]
        state.selectedSessionID = firstSessionID

        let items = state.sessionSwitcherItems
        #expect(items.count == 2)
        #expect(items[0].id == firstSessionID)
        #expect(items[1].id == secondSessionID)
    }

    @Test("sessionSwitcherItems includes each session's sandbox name")
    @MainActor
    func switcherItemsIncludeSandboxName() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let plainSessionID = state.sessions[0].id

        state.addSession(
            folderID: folderID,
            title: "Sandbox Shell",
            cwd: "/tmp",
            sandboxName: "development"
        )
        let sandboxSessionID = state.sessions[1].id

        let items = state.sessionSwitcherItems
        #expect(items.first { $0.id == plainSessionID }?.sandboxName == nil)
        #expect(items.first { $0.id == sandboxSessionID }?.sandboxName == "development")
    }

    @Test("sessionSwitcherItems includes each session's git branch")
    @MainActor
    func switcherItemsIncludeGitBranch() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let plainSessionID = state.sessions[0].id

        state.addSession(
            folderID: folderID,
            title: "Worktree Shell",
            cwd: "/tmp/worktree",
            worktreePath: "/tmp/worktree",
            branchName: "feature/session-switcher"
        )
        let worktreeSessionID = state.sessions[1].id

        #expect(state.sessionSwitcherItems.first { $0.id == plainSessionID }?.branchName == nil)
        #expect(
            state.sessionSwitcherItems.first { $0.id == worktreeSessionID }?.branchName
                == "feature/session-switcher"
        )
    }

    @Test("recordSessionKeyboardInput moves session to front of input MRU")
    @MainActor
    func keyboardInputMovesSessionToFront() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let firstSessionID = state.sessions[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let secondSessionID = state.sessions[1].id

        state.recordSessionKeyboardInput(sessionID: firstSessionID)
        state.recordSessionKeyboardInput(sessionID: secondSessionID)

        #expect(state.sessionInputMRUOrder == [secondSessionID, firstSessionID])
    }

    @Test("keyboard input refreshes the last input timestamp at most once per second")
    @MainActor
    func keyboardInputRecordsTimestamp() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id
        let firstInput = Date(timeIntervalSince1970: 1_700_000_000)
        let secondInput = firstInput.addingTimeInterval(0.2)
        let thirdInput = firstInput.addingTimeInterval(1.2)

        state.recordSessionKeyboardInput(sessionID: sessionID, at: firstInput)
        state.recordSessionKeyboardInput(sessionID: sessionID, at: secondInput)
        #expect(state.sessionLastInputAt[sessionID] == firstInput)

        state.recordSessionKeyboardInput(sessionID: sessionID, at: thirdInput)
        #expect(state.sessionLastInputAt[sessionID] == thirdInput)
    }

    @Test("session switcher captures a fixed relative-time reference when opened")
    @MainActor
    func switcherCapturesReferenceDate() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

        state.beginSessionSwitcher(at: referenceDate)

        #expect(state.sessionSwitcherReferenceDate == referenceDate)
    }

    @Test("selectMostRecentInputSession excludes currently selected session")
    @MainActor
    func selectMostRecentInputExcludesCurrent() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let firstSessionID = state.sessions[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let secondSessionID = state.sessions[1].id

        state.recordSessionKeyboardInput(sessionID: secondSessionID)
        state.recordSessionKeyboardInput(sessionID: firstSessionID)
        state.selectedSessionID = firstSessionID

        state.selectMostRecentInputSession()

        #expect(state.selectedSessionID == secondSessionID)
    }

    @Test("selectMostRecentInputSession walks backward through input history")
    @MainActor
    func selectMostRecentInputWalksBackward() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let firstSessionID = state.sessions[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let secondSessionID = state.sessions[1].id
        state.addSession(folderID: folderID, title: "Shell 3", cwd: "/tmp")
        let thirdSessionID = state.sessions[2].id
        state.addSession(folderID: folderID, title: "Shell 4", cwd: "/tmp")
        let fourthSessionID = state.sessions[3].id

        state.recordSessionKeyboardInput(sessionID: firstSessionID)
        state.recordSessionKeyboardInput(sessionID: secondSessionID)
        state.recordSessionKeyboardInput(sessionID: thirdSessionID)
        state.recordSessionKeyboardInput(sessionID: fourthSessionID)

        state.selectMostRecentInputSession()
        #expect(state.selectedSessionID == thirdSessionID)
        state.selectMostRecentInputSession()
        #expect(state.selectedSessionID == secondSessionID)
        state.selectMostRecentInputSession()
        #expect(state.selectedSessionID == firstSessionID)
    }

    @Test("selectMostRecentInputSession starts at newest from a normally selected middle entry")
    @MainActor
    func selectMostRecentInputStartsNewestFromMiddle() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let firstSessionID = state.sessions[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let secondSessionID = state.sessions[1].id
        state.addSession(folderID: folderID, title: "Shell 3", cwd: "/tmp")
        let thirdSessionID = state.sessions[2].id

        state.recordSessionKeyboardInput(sessionID: firstSessionID)
        state.recordSessionKeyboardInput(sessionID: secondSessionID)
        state.recordSessionKeyboardInput(sessionID: thirdSessionID)
        state.selectedSessionID = secondSessionID

        state.selectMostRecentInputSession()
        #expect(state.selectedSessionID == thirdSessionID)
        state.selectMostRecentInputSession()
        #expect(state.selectedSessionID == firstSessionID)
    }

    @Test("normal session selection resets input history traversal")
    @MainActor
    func normalSelectionResetsInputTraversal() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let firstSessionID = state.sessions[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let secondSessionID = state.sessions[1].id
        state.addSession(folderID: folderID, title: "Shell 3", cwd: "/tmp")
        let thirdSessionID = state.sessions[2].id

        state.recordSessionKeyboardInput(sessionID: firstSessionID)
        state.recordSessionKeyboardInput(sessionID: secondSessionID)
        state.recordSessionKeyboardInput(sessionID: thirdSessionID)

        state.selectMostRecentInputSession()
        #expect(state.selectedSessionID == secondSessionID)

        state.selectedSessionID = firstSessionID
        state.selectMostRecentInputSession()
        #expect(state.selectedSessionID == thirdSessionID)
    }

    @Test("new keyboard input resets input history traversal")
    @MainActor
    func keyboardInputResetsInputTraversal() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let firstSessionID = state.sessions[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let secondSessionID = state.sessions[1].id
        state.addSession(folderID: folderID, title: "Shell 3", cwd: "/tmp")
        let thirdSessionID = state.sessions[2].id

        state.recordSessionKeyboardInput(sessionID: firstSessionID)
        state.recordSessionKeyboardInput(sessionID: secondSessionID)
        state.recordSessionKeyboardInput(sessionID: thirdSessionID)

        state.selectMostRecentInputSession()
        #expect(state.selectedSessionID == secondSessionID)

        state.recordSessionKeyboardInput(sessionID: secondSessionID)
        state.selectMostRecentInputSession()
        #expect(state.selectedSessionID == thirdSessionID)
    }

    @Test("selectMostRecentInputSession stays at oldest input history entry")
    @MainActor
    func selectMostRecentInputStaysAtOldest() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let firstSessionID = state.sessions[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let secondSessionID = state.sessions[1].id

        state.recordSessionKeyboardInput(sessionID: firstSessionID)
        state.recordSessionKeyboardInput(sessionID: secondSessionID)

        state.selectMostRecentInputSession()
        #expect(state.selectedSessionID == firstSessionID)
        state.selectMostRecentInputSession()
        #expect(state.selectedSessionID == firstSessionID)
    }

    @Test("selectMostRecentInputSession starts at newest history when current is absent")
    @MainActor
    func selectMostRecentInputStartsAtNewestWhenCurrentAbsent() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let firstSessionID = state.sessions[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let secondSessionID = state.sessions[1].id

        state.recordSessionKeyboardInput(sessionID: firstSessionID)
        state.recordSessionKeyboardInput(sessionID: secondSessionID)
        state.selectedSessionID = UUID()

        state.selectMostRecentInputSession()

        #expect(state.selectedSessionID == secondSessionID)
    }

    @Test("selectMostRecentInputSession no-ops without another interacted session")
    @MainActor
    func selectMostRecentInputNoOtherSession() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let current = state.sessions[0].id

        state.recordSessionKeyboardInput(sessionID: current)
        state.selectMostRecentInputSession()

        #expect(state.selectedSessionID == current)
    }

    @Test("focus-only selection does not update input MRU")
    @MainActor
    func focusOnlyDoesNotUpdateInputMRU() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let firstSessionID = state.sessions[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let secondSessionID = state.sessions[1].id

        state.recordSessionKeyboardInput(sessionID: firstSessionID)
        state.selectedSessionID = secondSessionID

        #expect(state.sessionInputMRUOrder == [firstSessionID])
    }

    @Test("loaded input MRU filters stale session IDs")
    @MainActor
    func loadedInputMRUFiltersStaleIDs() {
        let folder = ManagedFolder(path: "/tmp", isGitRepo: false)
        let session = TerminalSession(folderID: folder.id, title: "Shell", workingDirectory: "/tmp")
        var persistedFolder = folder
        persistedFolder.sessionIDs = [session.id]
        let staleID = UUID()
        let persisted = PersistedState(
            folders: [persistedFolder],
            sessions: [session],
            selectedSessionID: session.id,
            sessionMRUOrder: [session.id],
            sessionInputMRUOrder: [staleID, session.id],
            sessionLastInputAt: [
                staleID: Date(timeIntervalSince1970: 1_600_000_000),
                session.id: Date(timeIntervalSince1970: 1_700_000_000),
            ]
        )

        let state = AppState(persistence: AppStateExtendedInMemoryPersistence(state: persisted))

        #expect(state.sessionInputMRUOrder == [session.id])
        #expect(Set(state.sessionLastInputAt.keys) == [session.id])
    }

    // MARK: - selectSessionByIndex

    @Test("selectSessionByIndex selects correct session")
    @MainActor
    func selectByIndex() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        state.addSession(folderID: folderID, title: "Shell 3", cwd: "/tmp")

        state.selectSessionByIndex(2)
        #expect(state.selectedSessionID == state.allSessionIDsOrdered[2])
    }

    @Test("selectSessionByIndex ignores out of bounds")
    @MainActor
    func selectByIndexOutOfBounds() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let current = state.selectedSessionID

        state.selectSessionByIndex(99)
        #expect(state.selectedSessionID == current)

        state.selectSessionByIndex(-1)
        #expect(state.selectedSessionID == current)
    }

    @Test("selectSession with reveal opens ancestors and requests sidebar scroll")
    @MainActor
    func selectSessionRevealsAncestors() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addGroup(name: "Backend")
        state.moveFolderToGroup(folderID: folderID, groupID: state.groups[0].id)
        state.setFolderExpanded(id: folderID, isExpanded: false)
        state.setGroupExpanded(id: state.groups[0].id, isExpanded: false)
        let sessionID = state.sessions[0].id

        state.selectSession(id: sessionID, revealInSidebar: true)

        #expect(state.selectedSessionID == sessionID)
        #expect(state.folders[0].isExpanded == true)
        #expect(state.groups[0].isExpanded == true)
        #expect(state.sidebarRevealSessionID == sessionID)
    }

    @Test("selectSession without reveal does not request sidebar scroll")
    @MainActor
    func selectSessionWithoutReveal() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id

        state.selectSession(id: sessionID)

        #expect(state.selectedSessionID == sessionID)
        #expect(state.sidebarRevealSessionID == nil)
    }

    // MARK: - Detail Tabs

    @Test("currentDetailTab defaults to terminal")
    @MainActor
    func defaultDetailTab() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        #expect(state.currentDetailTab == .terminal)
    }

    @Test("setDetailTab updates tab for session")
    @MainActor
    func setDetailTabUpdates() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id

        state.setDetailTab(.gitDiff, for: sessionID)
        #expect(state.detailTabBySession[sessionID] == .gitDiff)
    }

    @Test("toggleDetailTab cycles through terminal, gitDiff, and gitCommits")
    @MainActor
    func toggleDetailTab() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        // Mark folder as git repo so toggle works
        state.folders[0].isGitRepo = true
        let sessionID = state.sessions[0].id
        state.selectedSessionID = sessionID

        #expect(state.currentDetailTab == .terminal)
        state.toggleDetailTab()
        #expect(state.currentDetailTab == .gitDiff)
        state.toggleDetailTab()
        #expect(state.currentDetailTab == .gitCommits)
        state.toggleDetailTab()
        #expect(state.currentDetailTab == .terminal)
    }

    @Test("toggleDetailTab does nothing for non-git folder")
    @MainActor
    func toggleDetailTabNonGit() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.folders[0].isGitRepo = false

        state.toggleDetailTab()
        #expect(state.currentDetailTab == .terminal)
    }

    @Test("selectPreviousDetailTab goes from gitDiff to terminal")
    @MainActor
    func selectPreviousDetailTab() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.folders[0].isGitRepo = true
        let sessionID = state.sessions[0].id
        state.selectedSessionID = sessionID
        state.detailTabBySession[sessionID] = .gitDiff

        state.selectPreviousDetailTab()
        #expect(state.currentDetailTab == .terminal)
    }

    @Test("selectNextDetailTab goes from terminal to gitDiff")
    @MainActor
    func selectNextDetailTab() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.folders[0].isGitRepo = true
        let sessionID = state.sessions[0].id
        state.selectedSessionID = sessionID

        state.selectNextDetailTab()
        #expect(state.currentDetailTab == .gitDiff)
    }

    // MARK: - Git Status Helpers

    @Test("gitStatus for folder path returns stored status")
    @MainActor
    func gitStatusForFolderPath() {
        let state = makeCleanAppState()
        let status = GitStatus(linesAdded: 10, linesDeleted: 5, ahead: 1, behind: 0, currentBranch: "main")
        state.gitStatuses["/tmp/repo"] = status

        #expect(state.gitStatus(forFolderPath: "/tmp/repo") == status)
        #expect(state.gitStatus(forFolderPath: "/tmp/other") == nil)
    }

    @Test("gitStatus for session returns folder status")
    @MainActor
    func gitStatusForSession() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let session = state.sessions[0]
        let status = GitStatus(linesAdded: 3, linesDeleted: 1, ahead: 0, behind: 0, currentBranch: "main")
        state.gitStatuses["/tmp"] = status

        #expect(state.gitStatus(forSession: session) == status)
    }

    @Test("gitStatus for session with worktree uses worktree path")
    @MainActor
    func gitStatusForSessionWorktree() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(
            folderID: folderID,
            title: "WT",
            cwd: "/tmp/repo-termhub/feature",
            worktreePath: "/tmp/repo-termhub/feature",
            branchName: "feature"
        )
        let session = state.sessions.last!
        let wtStatus = GitStatus(linesAdded: 7, linesDeleted: 2, ahead: 0, behind: 0, currentBranch: "feature")
        state.gitStatuses["/tmp/repo-termhub/feature"] = wtStatus

        #expect(state.gitStatus(forSession: session) == wtStatus)
    }

    // MARK: - folderForSelectedSession

    @Test("folderForSelectedSession returns matching folder")
    @MainActor
    func folderForSelectedSession() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        #expect(state.folderForSelectedSession?.id == state.folders[0].id)
    }

    @Test("folderForSelectedSession returns nil when no selection")
    @MainActor
    func folderForSelectedSessionNil() {
        let state = makeCleanAppState()
        #expect(state.folderForSelectedSession == nil)
    }

    // MARK: - moveFolder

    @Test("moveFolder reorders folders")
    @MainActor
    func moveFolderReorders() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addFolder(path: "/var")
        let firstID = state.folders[0].id
        let secondID = state.folders[1].id

        state.moveFolder(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(state.folders[0].id == secondID)
        #expect(state.folders[1].id == firstID)
    }

    // MARK: - Rename

    @Test("startRenamingSession sets renaming state")
    @MainActor
    func startRenaming() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id

        state.startRenamingSession(id: sessionID)
        #expect(state.renamingSessionID == sessionID)
        #expect(state.renamingEditText == state.sessions[0].title)
    }

    @Test("finishRenamingSession clears renaming state")
    @MainActor
    func finishRenaming() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id

        state.startRenamingSession(id: sessionID)
        state.finishRenamingSession(id: sessionID)
        #expect(state.renamingSessionID == nil)
        #expect(state.renamingEditText == "")
    }

    @Test("renameSession sets hasCustomTitle flag")
    @MainActor
    func renameSessionSetsCustomTitle() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id

        state.renameSession(id: sessionID, newTitle: "Custom Name")
        #expect(state.sessions[0].hasCustomTitle == true)
    }

    // MARK: - sandboxInfo

    @Test("sandboxInfo returns matching sandbox by name")
    @MainActor
    func sandboxInfoFinds() {
        let state = makeCleanAppState()
        state.sandboxes = [
            SandboxInfo(name: "sb1", agent: "claude", status: "running", workspaces: []),
            SandboxInfo(name: "sb2", agent: "copilot", status: "stopped", workspaces: []),
        ]

        #expect(state.sandboxInfo(named: "sb1")?.agent == "claude")
        #expect(state.sandboxInfo(named: "sb2")?.isStopped == true)
        #expect(state.sandboxInfo(named: "sb3") == nil)
    }

    @Test("applicable sandboxes include only mapped session destinations")
    @MainActor
    func applicableSandboxesFiltersByWorkingDirectory() {
        let state = makeCleanAppState()
        state.sandboxes = [
            SandboxInfo(name: "project", agent: "claude", status: "running", workspaces: ["/projects/app"]),
            SandboxInfo(name: "shared", agent: "shell", status: "running", workspaces: ["/projects", "/tmp"]),
            SandboxInfo(name: "other", agent: "codex", status: "running", workspaces: ["/other"]),
        ]

        #expect(state.sandboxes(applicableTo: "/projects/app/worktree").map(\.name) == ["project", "shared"])
        #expect(state.sandboxes(applicableTo: "/projects/app-termhub/feature").map(\.name) == ["shared"])
        #expect(state.sandboxes(applicableTo: "/nowhere").isEmpty)
    }

    // MARK: - selectNextSessionNeedingAttention

    @Test("selectNextSessionNeedingAttention does nothing when no attention needed")
    @MainActor
    func selectNextAttentionEmpty() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let current = state.selectedSessionID

        state.selectNextSessionNeedingAttention()
        #expect(state.selectedSessionID == current)
    }

    // MARK: - allSessionIDsOrdered with worktrees

    @Test("allSessionIDsOrdered groups worktree sessions after plain sessions")
    @MainActor
    func orderedWithWorktrees() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let plainID = state.sessions[0].id

        state.addSession(
            folderID: folderID,
            title: "WT",
            cwd: "/tmp/wt",
            worktreePath: "/tmp/wt",
            branchName: "feature"
        )
        let wtID = state.sessions.last!.id

        let ordered = state.allSessionIDsOrdered
        #expect(ordered == [plainID, wtID])
    }

    // MARK: - Multiple folders navigation

    @Test("selectNextSession crosses folder boundaries")
    @MainActor
    func selectNextCrossesFolders() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addFolder(path: "/var")

        let firstFolderSession = state.folders[0].sessionIDs[0]
        let secondFolderSession = state.folders[1].sessionIDs[0]

        state.selectedSessionID = firstFolderSession
        state.selectNextSession()
        #expect(state.selectedSessionID == secondFolderSession)
    }

    @Test("selectPreviousSession crosses folder boundaries")
    @MainActor
    func selectPreviousCrossesFolders() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addFolder(path: "/var")

        let firstFolderSession = state.folders[0].sessionIDs[0]
        let secondFolderSession = state.folders[1].sessionIDs[0]

        state.selectedSessionID = secondFolderSession
        state.selectPreviousSession()
        #expect(state.selectedSessionID == firstFolderSession)
    }

    // MARK: - addSession with worktree

    @Test("addSession with worktree sets worktree properties")
    @MainActor
    func addSessionWithWorktree() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id

        state.addSession(
            folderID: folderID,
            title: "Feature Branch",
            cwd: "/tmp/wt/feature",
            worktreePath: "/tmp/wt/feature",
            branchName: "feature/login",
            isExternalWorktree: true,
            ownsBranch: true,
            sandboxName: "my-sandbox"
        )

        let session = state.sessions.last!
        #expect(session.worktreePath == "/tmp/wt/feature")
        #expect(session.branchName == "feature/login")
        #expect(session.isExternalWorktree == true)
        #expect(session.ownsBranch == true)
        #expect(session.sandboxName == "my-sandbox")
    }

    // MARK: - allSessionIDsOrdered with groups and sidebarOrder

    @Test("allSessionIDsOrdered respects sidebarOrder")
    @MainActor
    func orderedRespectssSidebarOrder() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addFolder(path: "/var")

        let firstSession = state.folders[0].sessionIDs[0]
        let secondSession = state.folders[1].sessionIDs[0]

        // Reverse the sidebar order
        state.sidebarOrder = [.folder(state.folders[1].id), .folder(state.folders[0].id)]

        let ordered = state.allSessionIDsOrdered
        #expect(ordered == [secondSession, firstSession])
    }

    @Test("allSessionIDsOrdered includes sessions from group folders")
    @MainActor
    func orderedWithGroup() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addFolder(path: "/var")

        let firstSession = state.folders[0].sessionIDs[0]
        let secondSession = state.folders[1].sessionIDs[0]

        // Put second folder into a group
        state.addGroup(name: "Backend")
        let groupID = state.groups[0].id
        state.moveFolderToGroup(folderID: state.folders[1].id, groupID: groupID)

        // sidebarOrder should be [.folder(first), .group(backend)]
        let ordered = state.allSessionIDsOrdered
        #expect(ordered == [firstSession, secondSession])
    }

    @Test("allSessionIDsOrdered skips collapsed group")
    @MainActor
    func orderedSkipsCollapsedGroup() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addFolder(path: "/var")

        let firstSession = state.folders[0].sessionIDs[0]

        state.addGroup(name: "Backend")
        let groupID = state.groups[0].id
        state.moveFolderToGroup(folderID: state.folders[1].id, groupID: groupID)
        state.setGroupExpanded(id: groupID, isExpanded: false)

        let ordered = state.allSessionIDsOrdered
        #expect(ordered == [firstSession])
    }

    @Test("allSessionIDsOrdered skips collapsed folder")
    @MainActor
    func orderedSkipsCollapsedFolder() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addFolder(path: "/var")

        let secondSession = state.folders[1].sessionIDs[0]

        state.setFolderExpanded(id: state.folders[0].id, isExpanded: false)

        let ordered = state.allSessionIDsOrdered
        #expect(ordered == [secondSession])
    }

    @Test("selectNextSession skips collapsed folder")
    @MainActor
    func selectNextSkipsCollapsedFolder() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addFolder(path: "/var")
        state.addFolder(path: "/usr")

        let firstSession = state.folders[0].sessionIDs[0]
        let thirdSession = state.folders[2].sessionIDs[0]

        // Collapse the middle folder
        state.setFolderExpanded(id: state.folders[1].id, isExpanded: false)

        state.selectedSessionID = firstSession
        state.selectNextSession()
        #expect(state.selectedSessionID == thirdSession)
    }

    @Test("affectedTrackedGitPaths returns only repos touched by watcher events")
    @MainActor
    func affectedTrackedGitPathsFiltersToTouchedRepos() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addFolder(path: "/private/tmp")
        state.folders[0].isGitRepo = true
        state.folders[1].isGitRepo = true

        mock.enqueueSuccess("/tmp/.git")
        mock.enqueueSuccess(".git")
        mock.enqueueSuccess("/private/tmp/.git")
        mock.enqueueSuccess(".git")

        let affected = state.affectedTrackedGitPaths(for: [
            "/tmp/.git/index.lock",
            "/tmp/src/main.swift",
            "/private/tmp/.git/refs/heads/main",
            "/other/location/file.txt"
        ])

        #expect(Set(affected) == Set(["/tmp", "/private/tmp"]))
    }

    @Test("affectedTrackedGitPaths excludes a session-only missing worktree path")
    @MainActor
    func affectedTrackedGitPathsIncludesWorktreeForGitAdminChanges() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.folders[0].isGitRepo = true
        let folderID = state.folders[0].id
        let worktreeSession = TerminalSession(
            folderID: folderID,
            title: "feature",
            workingDirectory: "/tmp/repo-termhub/feature",
            worktreePath: "/tmp/repo-termhub/feature",
            branchName: "feature",
            folderName: state.folders[0].name
        )
        state.sessions.append(worktreeSession)
        state.folders[0].sessionIDs.append(worktreeSession.id)

        mock.enqueueSuccess("/tmp/.git")
        mock.enqueueSuccess(".git")
        mock.enqueueSuccess("/tmp/.git/worktrees/feature")
        mock.enqueueSuccess("/tmp/.git")

        let affected = state.affectedTrackedGitPaths(for: [
            "/tmp/.git/worktrees/feature/index"
        ])

        #expect(!affected.contains("/tmp/repo-termhub/feature"))
    }

    @Test("applyDetectedGitRepos hydrates branch status for newly detected folders")
    @MainActor
    func applyDetectedGitReposHydratesBranchStatus() async throws {
        mock.reset()
        mock.handler = { _, arguments, _ in
            if arguments.contains("--absolute-git-dir") {
                return CommandResult(output: "/tmp/.git", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("--git-common-dir") {
                return CommandResult(output: ".git", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("diff") {
                return CommandResult(output: "", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("ls-files") {
                return CommandResult(output: "", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("rev-list") {
                return CommandResult(output: "0\t0", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("symbolic-ref") || arguments.contains("--show-current") {
                return CommandResult(output: "main", errorOutput: "", exitCode: 0)
            }
            return CommandResult(output: "", errorOutput: "", exitCode: 0)
        }

        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.folders[0].isGitRepo = false
        state.gitStatuses.removeAll()

        state.applyDetectedGitRepos(atPaths: ["/tmp"])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(state.folders[0].isGitRepo == true)
        #expect(state.gitStatuses["/tmp"]?.currentBranch == "main")
    }

    @Test("adding a Git folder detects it and hydrates its status")
    @MainActor
    func addFolderDetectsGitRepo() async throws {
        mock.reset()
        mock.handler = { _, arguments, _ in
            if arguments.contains("rev-parse"), arguments.contains("--git-dir") {
                return CommandResult(output: ".git", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("diff") {
                return CommandResult(output: "", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("ls-files") {
                return CommandResult(output: "", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("rev-list") {
                return CommandResult(output: "0\t0", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("symbolic-ref") || arguments.contains("--show-current") {
                return CommandResult(output: "main", errorOutput: "", exitCode: 0)
            }
            return CommandResult(output: "", errorOutput: "", exitCode: 0)
        }

        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(state.folders[0].isGitRepo == true)
        #expect(state.gitStatuses["/tmp"]?.currentBranch == "main")
    }

    @Test("targeted Git refresh preserves statuses for other tracked folders")
    @MainActor
    func targetedGitRefreshPreservesOtherStatuses() async throws {
        mock.reset()
        mock.handler = { _, arguments, _ in
            let path = arguments.count > 1 ? arguments[1] : ""
            if arguments.contains("rev-parse"), arguments.contains("--git-dir") {
                return CommandResult(output: ".git", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("rev-parse"), arguments.contains("--verify") {
                return CommandResult(output: "abc123", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("diff") {
                let output = path == "/tmp" ? "8\t3\tApp.swift" : ""
                return CommandResult(output: output, errorOutput: "", exitCode: 0)
            }
            if arguments.contains("ls-files") {
                return CommandResult(output: "", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("rev-list") {
                return CommandResult(output: "0\t0", errorOutput: "", exitCode: 0)
            }
            if arguments.contains("--show-current") {
                return CommandResult(output: path == "/tmp" ? "main" : "develop", errorOutput: "", exitCode: 0)
            }
            return CommandResult(output: "", errorOutput: "", exitCode: 0)
        }

        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addFolder(path: "/var")
        state.folders[0].isGitRepo = true
        state.folders[1].isGitRepo = true
        try await Task.sleep(nanoseconds: 100_000_000)

        let otherStatus = GitStatus(linesAdded: 5, linesDeleted: 2, ahead: 0, behind: 0, currentBranch: "develop")
        state.gitStatuses["/var"] = otherStatus
        state.refreshGitStatuses(for: ["/tmp"])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(state.gitStatuses["/tmp"]?.currentBranch == "main")
        #expect(state.gitStatuses["/tmp"]?.linesAdded == 8)
        #expect(state.gitStatuses["/tmp"]?.linesDeleted == 3)
        #expect(state.gitStatuses["/var"] == otherStatus)
    }

    @Test("failed Git refresh keeps the last known status")
    @MainActor
    func failedGitRefreshKeepsLastStatus() async throws {
        mock.reset()
        mock.handler = { _, arguments, _ in
            if arguments.contains("rev-parse"), arguments.contains("--git-dir") {
                return CommandResult(output: "", errorOutput: "fatal: worktree unavailable", exitCode: 1)
            }
            return CommandResult(output: "", errorOutput: "", exitCode: 0)
        }

        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.folders[0].isGitRepo = true
        let previous = GitStatus(linesAdded: 6, linesDeleted: 1, ahead: 0, behind: 0, currentBranch: "main")
        state.gitStatuses["/tmp"] = previous

        state.refreshGitStatuses(for: ["/tmp"])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(state.gitStatuses["/tmp"] == previous)
    }
}

private final class AppStateExtendedInMemoryPersistence: StatePersistence, @unchecked Sendable {
    private var state: PersistedState

    init(state: PersistedState) {
        self.state = state
    }

    func save(state: PersistedState) throws {
        self.state = state
    }

    func load() throws -> PersistedState {
        state
    }

    func scheduleWrite(_ work: @escaping @Sendable () -> Void) {
        work()
    }
}
