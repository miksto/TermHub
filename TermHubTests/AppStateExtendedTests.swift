import Foundation
import Testing
@testable import TermHub

@Suite("AppState Extended Tests")
struct AppStateExtendedTests {

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

    @Test("toggleDetailTab switches between terminal and gitDiff")
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
}
