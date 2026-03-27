import Foundation
import Testing
@testable import TermHub

@Suite("AppState Tests")
struct AppStateTests {

    @MainActor
    private func makeCleanAppState() -> AppState {
        AppState(persistence: NullPersistence())
    }

    @Test("addFolder with existing path creates folder and default session")
    @MainActor
    func addFolderCreatesDefaultSession() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")

        #expect(state.folders.count == 1)
        #expect(state.folders[0].name == "tmp")
        #expect(state.sessions.count == 1)
        #expect(state.sessions[0].folderID == state.folders[0].id)
        #expect(state.sessions[0].title == "tmp")
        #expect(state.folders[0].sessionIDs.count == 1)
        #expect(state.folders[0].sessionIDs[0] == state.sessions[0].id)
    }

    @Test("addFolder auto-selects session when none selected")
    @MainActor
    func addFolderAutoSelects() {
        let state = makeCleanAppState()
        #expect(state.selectedSessionID == nil)

        state.addFolder(path: "/tmp")
        #expect(state.selectedSessionID == state.sessions[0].id)
    }

    @Test("addFolder with non-existent path sets error message")
    @MainActor
    func addFolderNonExistentPath() {
        let state = makeCleanAppState()
        state.addFolder(path: "/nonexistent/path/that/does/not/exist/12345")

        #expect(state.folders.isEmpty)
        #expect(state.sessions.isEmpty)
        #expect(state.errorMessage != nil)
        #expect(state.errorMessage!.contains("does not exist"))
    }

    @Test("removeFolder cascades to remove all sessions")
    @MainActor
    func removeFolderCascades() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id

        // Add a second session to the same folder
        state.addSession(folderID: folderID, title: "Extra Shell", cwd: "/tmp")
        #expect(state.sessions.count == 2)

        state.removeFolder(id: folderID)
        #expect(state.folders.isEmpty)
        #expect(state.sessions.isEmpty)
    }

    @Test("removeSession clears selection when removing selected session")
    @MainActor
    func removeSessionClearsSelection() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id
        #expect(state.selectedSessionID == sessionID)

        state.removeSession(id: sessionID)
        // With only one session in the folder, removal should result in nil selection
        // (no siblings or other sessions to select)
        #expect(state.sessions.isEmpty)
    }

    @Test("removeSession auto-selects next sibling")
    @MainActor
    func removeSessionAutoSelectsSibling() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        let firstSessionID = state.sessions[0].id

        // Add second session
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        let secondSessionID = state.sessions[1].id

        // Select first, then remove it — should auto-select second
        state.selectedSessionID = firstSessionID
        state.removeSession(id: firstSessionID)
        #expect(state.selectedSessionID == secondSessionID)
    }

    @Test("addSession adds to folder's sessionIDs")
    @MainActor
    func addSessionUpdatesFolder() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        #expect(state.folders[0].sessionIDs.count == 1)

        state.addSession(folderID: folderID, title: "New Shell", cwd: "/tmp")
        #expect(state.folders[0].sessionIDs.count == 2)
        #expect(state.sessions.count == 2)
    }

    @Test("addSession selects the new session")
    @MainActor
    func addSessionSelectsNew() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id

        state.addSession(folderID: folderID, title: "New Shell", cwd: "/tmp")
        #expect(state.selectedSessionID == state.sessions.last?.id)
    }

    @Test("renameSession updates title")
    @MainActor
    func renameSession() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id

        state.renameSession(id: sessionID, newTitle: "Renamed")
        #expect(state.sessions[0].title == "Renamed")
    }

    @Test("selectNextSession moves forward")
    @MainActor
    func selectNextSession() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")
        state.addSession(folderID: folderID, title: "Shell 3", cwd: "/tmp")

        state.selectedSessionID = state.sessions[0].id
        state.selectNextSession()
        #expect(state.selectedSessionID == state.sessions[1].id)
    }

    @Test("selectPreviousSession moves backward")
    @MainActor
    func selectPreviousSession() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")

        state.selectedSessionID = state.sessions[1].id
        state.selectPreviousSession()
        #expect(state.selectedSessionID == state.sessions[0].id)
    }

    @Test("selectNextSession at end does not wrap")
    @MainActor
    func selectNextSessionAtEnd() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let lastID = state.sessions[0].id
        state.selectedSessionID = lastID

        state.selectNextSession()
        #expect(state.selectedSessionID == lastID)
    }

    @Test("selectPreviousSession at beginning does not wrap")
    @MainActor
    func selectPreviousSessionAtBeginning() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let firstID = state.sessions[0].id
        state.selectedSessionID = firstID

        state.selectPreviousSession()
        #expect(state.selectedSessionID == firstID)
    }

    @Test("allSessionIDsOrdered returns sessions in folder order")
    @MainActor
    func allSessionIDsOrdered() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(folderID: folderID, title: "Shell 2", cwd: "/tmp")

        let ordered = state.allSessionIDsOrdered
        #expect(ordered.count == 2)
        #expect(ordered[0] == state.folders[0].sessionIDs[0])
        #expect(ordered[1] == state.folders[0].sessionIDs[1])
    }

    @Test("selectedSession returns nil when no selection")
    @MainActor
    func selectedSessionNil() {
        let state = makeCleanAppState()
        #expect(state.selectedSession == nil)
    }

    @Test("selectedSession returns matching session")
    @MainActor
    func selectedSessionMatches() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id
        state.selectedSessionID = sessionID

        #expect(state.selectedSession?.id == sessionID)
    }

    @Test("assistant clear chat removes all messages")
    @MainActor
    func assistantClearChat() {
        let state = makeCleanAppState()
        state.assistantMessages = [
            AssistantMessage(role: .user, content: "hello"),
            AssistantMessage(role: .assistant, content: "hi")
        ]

        state.clearAssistantChat()
        #expect(state.assistantMessages.isEmpty)
    }
}
