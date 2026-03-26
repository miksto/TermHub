import Foundation
import Testing
@testable import TermHub

@Suite("IPCServer Tests")
struct IPCServerTests {

    @MainActor
    private func makeServerAndState() -> (IPCServer, AppState) {
        let state = AppState(persistence: NullPersistence())
        let server = IPCServer(appState: state)
        return (server, state)
    }

    private func encode(_ request: IPCRequest) -> Data {
        try! JSONEncoder().encode(request)
    }

    // MARK: - listSessions

    @Test("listSessions returns empty array when no sessions")
    @MainActor
    func listSessionsEmpty() async {
        let (server, state) = makeServerAndState()
        _ = state // prevent deallocation
        let response = await server.handleRequest(data: encode(IPCRequest(action: "listSessions", params: nil)))
        #expect(response.ok)
        if case .array(let sessions) = response.data {
            #expect(sessions.isEmpty)
        } else {
            Issue.record("Expected array data")
        }
    }

    @Test("listSessions returns sessions after adding a folder")
    @MainActor
    func listSessionsAfterAddFolder() async {
        let (server, state) = makeServerAndState()
        state.addFolder(path: "/tmp")

        let response = await server.handleRequest(data: encode(IPCRequest(action: "listSessions", params: nil)))
        #expect(response.ok)
        if case .array(let sessions) = response.data {
            #expect(sessions.count == 1)
            if case .object(let session) = sessions[0] {
                #expect(session["title"]?.stringValue == "tmp")
                #expect(session["isSelected"]?.boolValue == true)
            }
        } else {
            Issue.record("Expected array data")
        }
    }

    // MARK: - listFolders

    @Test("listFolders returns empty array when no folders")
    @MainActor
    func listFoldersEmpty() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(action: "listFolders", params: nil)))
        #expect(response.ok)
        if case .array(let folders) = response.data {
            #expect(folders.isEmpty)
        } else {
            Issue.record("Expected array data")
        }
    }

    @Test("listFolders returns folder details")
    @MainActor
    func listFoldersWithData() async {
        let (server, state) = makeServerAndState()
        state.addFolder(path: "/tmp")

        let response = await server.handleRequest(data: encode(IPCRequest(action: "listFolders", params: nil)))
        #expect(response.ok)
        if case .array(let folders) = response.data {
            #expect(folders.count == 1)
            if case .object(let folder) = folders[0] {
                #expect(folder["name"]?.stringValue == "tmp")
                #expect(folder["path"]?.stringValue == "/tmp")
                #expect(folder["sessionCount"]?.intValue == 1)
            }
        } else {
            Issue.record("Expected array data")
        }
    }

    // MARK: - addFolder

    @Test("addFolder creates folder and returns id")
    @MainActor
    func addFolderSuccess() async {
        let (server, state) = makeServerAndState()
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "addFolder",
            params: ["path": .string("/tmp")]
        )))
        #expect(response.ok)
        #expect(state.folders.count == 1)
        #expect(state.folders[0].name == "tmp")
        if case .object(let data) = response.data {
            #expect(data["name"]?.stringValue == "tmp")
            #expect(data["id"]?.stringValue != nil)
        }
    }

    @Test("addFolder fails for nonexistent path")
    @MainActor
    func addFolderBadPath() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "addFolder",
            params: ["path": .string("/nonexistent/path/that/does/not/exist")]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("does not exist") == true)
    }

    @Test("addFolder fails for duplicate path")
    @MainActor
    func addFolderDuplicate() async {
        let (server, state) = makeServerAndState()
        state.addFolder(path: "/tmp")
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "addFolder",
            params: ["path": .string("/tmp")]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("already added") == true)
    }

    @Test("addFolder fails when path param is missing")
    @MainActor
    func addFolderMissingParam() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "addFolder",
            params: [:]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("Missing") == true)
    }

    // MARK: - removeFolder

    @Test("removeFolder removes folder and its sessions")
    @MainActor
    func removeFolderSuccess() async {
        let (server, state) = makeServerAndState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id

        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "removeFolder",
            params: ["folderId": .string(folderID.uuidString)]
        )))
        #expect(response.ok)
        #expect(state.folders.isEmpty)
        #expect(state.sessions.isEmpty)
    }

    @Test("removeFolder fails for unknown ID")
    @MainActor
    func removeFolderUnknown() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "removeFolder",
            params: ["folderId": .string(UUID().uuidString)]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("not found") == true)
    }

    // MARK: - addSession

    @Test("addSession creates session in existing folder")
    @MainActor
    func addSessionSuccess() async {
        let (server, state) = makeServerAndState()
        state.addFolder(path: "/tmp")

        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "addSession",
            params: [
                "folderPath": .string("/tmp"),
                "title": .string("my-session"),
            ]
        )))
        #expect(response.ok)
        // 1 default from addFolder + 1 new
        #expect(state.sessions.count == 2)
        #expect(state.sessions[1].title == "my-session")
        if case .object(let data) = response.data {
            #expect(data["id"]?.stringValue != nil)
            #expect(data["tmuxSessionName"]?.stringValue != nil)
        }
    }

    @Test("addSession fails for unknown folder")
    @MainActor
    func addSessionUnknownFolder() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "addSession",
            params: ["folderPath": .string("/nonexistent")]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("Folder not found") == true)
    }

    // MARK: - removeSession

    @Test("removeSession removes the session")
    @MainActor
    func removeSessionSuccess() async {
        let (server, state) = makeServerAndState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id

        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "removeSession",
            params: ["sessionId": .string(sessionID.uuidString)]
        )))
        #expect(response.ok)
        #expect(state.sessions.isEmpty)
    }

    @Test("removeSession fails for unknown ID")
    @MainActor
    func removeSessionUnknown() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "removeSession",
            params: ["sessionId": .string(UUID().uuidString)]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("not found") == true)
    }

    // MARK: - selectSession

    @Test("selectSession changes the selected session")
    @MainActor
    func selectSessionSuccess() async {
        let (server, state) = makeServerAndState()
        state.addFolder(path: "/tmp")
        state.addSession(folderID: state.folders[0].id, title: "second", cwd: "/tmp")
        let secondID = state.sessions[1].id

        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "selectSession",
            params: ["sessionId": .string(secondID.uuidString)]
        )))
        #expect(response.ok)
        #expect(state.selectedSessionID == secondID)
    }

    @Test("selectSession fails for unknown ID")
    @MainActor
    func selectSessionUnknown() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "selectSession",
            params: ["sessionId": .string(UUID().uuidString)]
        )))
        #expect(!response.ok)
    }

    // MARK: - renameSession

    @Test("renameSession updates session title")
    @MainActor
    func renameSessionSuccess() async {
        let (server, state) = makeServerAndState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id

        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "renameSession",
            params: [
                "sessionId": .string(sessionID.uuidString),
                "newTitle": .string("renamed"),
            ]
        )))
        #expect(response.ok)
        #expect(state.sessions[0].title == "renamed")
        #expect(state.sessions[0].hasCustomTitle == true)
    }

    @Test("renameSession fails without newTitle")
    @MainActor
    func renameSessionMissingTitle() async {
        let (server, state) = makeServerAndState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id

        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "renameSession",
            params: ["sessionId": .string(sessionID.uuidString)]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("newTitle") == true)
    }

    // MARK: - Unknown action

    @Test("unknown action returns error")
    @MainActor
    func unknownAction() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "nonexistentAction",
            params: nil
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("Unknown action") == true)
    }

    // MARK: - listSandboxes

    @Test("listSandboxes returns empty array when no sandboxes")
    @MainActor
    func listSandboxesEmpty() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(action: "listSandboxes", params: nil)))
        #expect(response.ok)
        if case .array(let sandboxes) = response.data {
            #expect(sandboxes.isEmpty)
        } else {
            Issue.record("Expected array data")
        }
    }

    // MARK: - createSandbox

    @Test("createSandbox fails when name is missing")
    @MainActor
    func createSandboxMissingName() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "createSandbox",
            params: ["workspaces": .array([.string("/tmp")])]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("name") == true)
    }

    @Test("createSandbox fails when workspaces is missing")
    @MainActor
    func createSandboxMissingWorkspaces() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "createSandbox",
            params: ["name": .string("test-sandbox")]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("workspaces") == true)
    }

    @Test("createSandbox fails when workspaces is empty")
    @MainActor
    func createSandboxEmptyWorkspaces() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "createSandbox",
            params: ["name": .string("test-sandbox"), "workspaces": .array([])]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("at least one") == true)
    }

    @Test("createSandbox fails for invalid agent")
    @MainActor
    func createSandboxInvalidAgent() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "createSandbox",
            params: [
                "name": .string("test-sandbox"),
                "agent": .string("invalid-agent"),
                "workspaces": .array([.string("/tmp")]),
            ]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("Invalid agent") == true)
    }

    // MARK: - stopSandbox

    @Test("stopSandbox fails when name is missing")
    @MainActor
    func stopSandboxMissingName() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "stopSandbox",
            params: [:]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("name") == true)
    }

    // MARK: - removeSandbox

    @Test("removeSandbox fails when name is missing")
    @MainActor
    func removeSandboxMissingName() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "removeSandbox",
            params: [:]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("name") == true)
    }

    // MARK: - createWorktree

    @Test("createWorktree fails when folderPath is missing")
    @MainActor
    func createWorktreeMissingFolderPath() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "createWorktree",
            params: ["branch": .string("feature")]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("folderPath") == true)
    }

    @Test("createWorktree fails when branch is missing")
    @MainActor
    func createWorktreeMissingBranch() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "createWorktree",
            params: ["folderPath": .string("/tmp")]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("branch") == true)
    }

    @Test("createWorktree fails for unknown folder")
    @MainActor
    func createWorktreeUnknownFolder() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "createWorktree",
            params: ["folderPath": .string("/nonexistent"), "branch": .string("feature")]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("Folder not found") == true)
    }

    @Test("createWorktree fails for non-git folder")
    @MainActor
    func createWorktreeNonGitFolder() async {
        let (server, state) = makeServerAndState()
        state.addFolder(path: "/tmp")

        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "createWorktree",
            params: ["folderPath": .string("/tmp"), "branch": .string("feature")]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("not a git repo") == true)
    }

    // MARK: - addSession with optional params

    @Test("addSession with worktree and sandbox params")
    @MainActor
    func addSessionWithOptionalParams() async {
        let (server, state) = makeServerAndState()
        state.addFolder(path: "/tmp")

        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "addSession",
            params: [
                "folderPath": .string("/tmp"),
                "title": .string("worktree-session"),
                "worktreePath": .string("/tmp/worktree"),
                "branchName": .string("feature-branch"),
                "sandboxName": .string("my-sandbox"),
            ]
        )))
        #expect(response.ok)
        let session = state.sessions.last!
        #expect(session.title == "worktree-session")
        #expect(session.worktreePath == "/tmp/worktree")
        #expect(session.branchName == "feature-branch")
        #expect(session.sandboxName == "my-sandbox")
    }

    @Test("addSession missing folderPath param")
    @MainActor
    func addSessionMissingFolderPath() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "addSession",
            params: ["title": .string("test")]
        )))
        #expect(!response.ok)
        #expect(response.error?.contains("folderPath") == true)
    }

    // MARK: - removeSession with invalid UUID

    @Test("removeSession fails for invalid UUID format")
    @MainActor
    func removeSessionInvalidUUID() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "removeSession",
            params: ["sessionId": .string("not-a-uuid")]
        )))
        #expect(!response.ok)
    }

    // MARK: - selectSession with invalid UUID

    @Test("selectSession fails for invalid UUID format")
    @MainActor
    func selectSessionInvalidUUID() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "selectSession",
            params: ["sessionId": .string("not-a-uuid")]
        )))
        #expect(!response.ok)
    }

    // MARK: - removeFolder with invalid UUID

    @Test("removeFolder fails for invalid UUID format")
    @MainActor
    func removeFolderInvalidUUID() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: encode(IPCRequest(
            action: "removeFolder",
            params: ["folderId": .string("not-a-uuid")]
        )))
        #expect(!response.ok)
    }

    // MARK: - Invalid JSON

    @Test("invalid JSON returns error")
    @MainActor
    func invalidJSON() async {
        let (server, state) = makeServerAndState()
        _ = state
        let response = await server.handleRequest(data: Data("not json".utf8))
        #expect(!response.ok)
        #expect(response.error?.contains("Invalid JSON") == true)
    }
}
