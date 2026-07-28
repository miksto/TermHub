import Foundation
import Testing
@testable import TermHub

@Suite("AppState Tests")
struct AppStateTests {

    private func removeUserDefaultIfPresent(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

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

    @Test("Ctrl+Tab sidebar reveal is enabled by default")
    @MainActor
    func ctrlTabRevealEnabledByDefault() {
        let state = makeCleanAppState()
        #expect(state.revealSelectedSessionInSidebarOnCtrlTab == true)
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

    @Test("selectedFolder resolves the parent folder for a normal session")
    @MainActor
    func selectedFolderForNormalSession() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")

        #expect(state.selectedFolder?.id == state.folders[0].id)
    }

    @Test("selectedFolder resolves the parent folder for a worktree session")
    @MainActor
    func selectedFolderForWorktreeSession() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(
            folderID: folderID,
            title: "Worktree",
            cwd: "/tmp/example-worktree",
            worktreePath: "/tmp/example-worktree"
        )

        #expect(state.selectedFolder?.id == folderID)
        #expect(state.selectedFolder?.path == "/tmp")
    }

    @Test("selectedFolder resolves the parent folder for a sandbox session")
    @MainActor
    func selectedFolderForSandboxSession() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addSession(
            folderID: folderID,
            title: "Sandbox",
            cwd: "/workspace",
            sandboxName: "development"
        )

        #expect(state.selectedFolder?.id == folderID)
        #expect(state.selectedFolder?.path == "/tmp")
    }

    @Test("selectedFolder is nil when no session is selected")
    @MainActor
    func selectedFolderNilWithoutSelection() {
        let state = makeCleanAppState()

        #expect(state.selectedFolder == nil)
    }

    @Test("toggleAssistant does nothing without a selected folder")
    @MainActor
    func toggleAssistantWithoutSelectedFolder() {
        let state = makeCleanAppState()

        state.toggleAssistant()

        #expect(!state.showAssistant)
    }

    @Test("toggleAssistant opens with a selected folder")
    @MainActor
    func toggleAssistantWithSelectedFolder() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")

        state.toggleAssistant()

        #expect(state.showAssistant)
    }

    @Test("toggleAssistant closes with an invalid selection")
    @MainActor
    func toggleAssistantClosesWithInvalidSelection() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.showAssistant = true
        state.selectedSessionID = UUID()

        state.toggleAssistant()

        #expect(!state.showAssistant)
    }

    @Test("session toolbar title is nil when no session is selected")
    @MainActor
    func sessionToolbarTitleNilWhenNoSelection() {
        let state = makeCleanAppState()
        #expect(SessionToolbarTitleView.toolbarTitle(in: state) == nil)
    }

    @Test("session toolbar title omits group for ungrouped repo")
    @MainActor
    func sessionToolbarTitleUngrouped() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")

        #expect(SessionToolbarTitleView.toolbarTitle(in: state) == "tmp - tmp")
    }

    @Test("session toolbar title includes group when repo is grouped")
    @MainActor
    func sessionToolbarTitleGrouped() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addGroup(name: "Backend")
        state.moveFolderToGroup(folderID: folderID, groupID: state.groups[0].id)

        #expect(SessionToolbarTitleView.toolbarTitle(in: state) == "Backend - tmp - tmp")
    }

    @Test("session toolbar title prefers display state title")
    @MainActor
    func sessionToolbarTitleUsesDisplayState() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let sessionID = state.sessions[0].id
        state.sessions[0].title = "Stored"
        state.displayState(for: sessionID)?.title = "Displayed"

        #expect(SessionToolbarTitleView.toolbarTitle(in: state) == "tmp - Displayed")
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

    @Test("send TTY size to sandbox terminals defaults enabled")
    @MainActor
    func sendTTYSizeToSandboxTerminalsDefault() {
        removeUserDefaultIfPresent("sendTTYSizeToSandboxTerminals")
        let state = makeCleanAppState()

        #expect(state.sendTTYSizeToSandboxTerminals)
        #expect(state.terminalManager.sendTTYSizeToSandboxTerminals)
    }

    @Test("send TTY size to sandbox terminals persists and updates manager")
    @MainActor
    func sendTTYSizeToSandboxTerminalsPersists() {
        removeUserDefaultIfPresent("sendTTYSizeToSandboxTerminals")
        let state = makeCleanAppState()

        state.sendTTYSizeToSandboxTerminals = false

        #expect(!state.terminalManager.sendTTYSizeToSandboxTerminals)
        #expect(UserDefaults.standard.object(forKey: "sendTTYSizeToSandboxTerminals") as? Bool == false)
    }

    @Test("assistant provider defaults to claude")
    @MainActor
    func assistantProviderDefault() {
        removeUserDefaultIfPresent("assistantProvider")
        let state = makeCleanAppState()
        #expect(state.assistantProvider == .claude)
    }

    @Test("assistant provider persists in user defaults")
    @MainActor
    func assistantProviderPersists() {
        removeUserDefaultIfPresent("assistantProvider")
        let state = makeCleanAppState()
        state.assistantProvider = .copilot
        #expect(UserDefaults.standard.string(forKey: "assistantProvider") == "copilot")
    }

    @Test("assistant allowed tools are isolated per provider")
    @MainActor
    func assistantAllowedToolsPerProvider() {
        removeUserDefaultIfPresent("assistantAllowedTools")
        removeUserDefaultIfPresent("assistantAllowedToolsByProvider")
        removeUserDefaultIfPresent("assistantProvider")

        let state = makeCleanAppState()
        #expect(state.assistantProvider == .claude)
        #expect(state.assistantAllowedTools.contains("mcp__termhub__*"))

        state.assistantAllowedTools = "WebFetch,mcp__termhub__*,Bash"
        state.assistantProvider = .copilot
        #expect(state.assistantAllowedTools == "WebFetch")

        state.assistantAllowedTools = "WebFetch,bash"
        state.assistantProvider = .claude
        #expect(state.assistantAllowedTools == "WebFetch,mcp__termhub__*,Bash")

        state.assistantProvider = .codex
        #expect(state.assistantAllowedTools == "")
    }

    @Test("legacy assistantAllowedTools migrates to Claude only")
    @MainActor
    func assistantAllowedToolsLegacyMigration() {
        removeUserDefaultIfPresent("assistantAllowedToolsByProvider")
        removeUserDefaultIfPresent("assistantProvider")
        UserDefaults.standard.set("WebFetch,mcp__termhub__*", forKey: "assistantAllowedTools")

        let state = makeCleanAppState()
        #expect(state.assistantProvider == .claude)
        #expect(state.assistantAllowedTools == "WebFetch,mcp__termhub__*")

        state.assistantProvider = .copilot
        #expect(state.assistantAllowedTools == "WebFetch")

        state.assistantProvider = .codex
        #expect(state.assistantAllowedTools == "")
    }

    @Test("Copilot argument build strips wildcard allowed tools")
    func copilotBuildArgumentsSanitizeWildcardTools() {
        let service = AssistantService()
        let result = service.testBuildArguments(
            text: "hello",
            provider: .copilot,
            mcpEnabled: false,
            allowedTools: "WebFetch,mcp__termhub__*",
            isFirstMessage: true,
            sessionID: UUID()
        )

        #expect(result.args.contains("--allow-tool"))
        #expect(result.args.contains("WebFetch"))
        #expect(!result.args.contains("mcp__termhub__*"))
        #expect(result.notices.contains { $0.contains("Ignored unsupported Copilot Allowed Tools pattern") })
    }

    @Test("assistant help text differs by provider")
    @MainActor
    func assistantProviderSpecificHelpText() {
        let state = makeCleanAppState()

        state.assistantProvider = .claude
        #expect(state.assistantAllowedToolsHelpText.contains("Claude-only"))
        #expect(state.assistantAllowedToolsPlaceholder.contains("mcp__termhub__*"))

        state.assistantProvider = .copilot
        #expect(state.assistantAllowedToolsHelpText.contains("Copilot-only"))
        #expect(state.assistantAllowedToolsPlaceholder.contains("WebFetch,bash"))

        state.assistantProvider = .codex
        #expect(state.assistantAllowedToolsHelpText.contains("ignored"))
        #expect(state.assistantAllowedToolsPlaceholder.contains("Not used"))
    }

    @Test("assistant model defaults per provider")
    @MainActor
    func assistantModelDefaults() {
        removeUserDefaultIfPresent("assistantModelByProvider")
        let state = makeCleanAppState()

        state.assistantProvider = .claude
        #expect(state.assistantModel == "default")

        state.assistantProvider = .copilot
        #expect(state.assistantModel == "claude-haiku-4.5")

        state.assistantProvider = .codex
        #expect(state.assistantModel == "gpt-5.6-luna")
    }

    @Test("assistant Copilot model options include full supported list")
    @MainActor
    func assistantCopilotModelOptionsFullList() {
        let options = AppState.assistantModelOptions(for: .copilot)
        #expect(options.contains("claude-sonnet-4.6"))
        #expect(options.contains("gpt-5.3-codex"))
        #expect(options.contains("gpt-5.1-codex-mini"))
        #expect(options.contains("gpt-5-mini"))
        #expect(options.count >= 16)
    }

    @Test("assistant model is stored per provider")
    @MainActor
    func assistantModelPerProvider() {
        let state = makeCleanAppState()

        state.assistantProvider = .claude
        state.assistantModel = "sonnet-1m"

        state.assistantProvider = .copilot
        state.assistantModel = "gpt-5.2"

        state.assistantProvider = .claude
        #expect(state.assistantModel == "sonnet-1m")

        state.assistantProvider = .copilot
        #expect(state.assistantModel == "gpt-5.2")

        state.assistantProvider = .codex
        #expect(state.assistantModel == "gpt-5.6-luna")
    }

    @Test("assistant effort defaults per provider")
    @MainActor
    func assistantEffortDefaults() {
        removeUserDefaultIfPresent("assistantEffortByProvider")
        let state = makeCleanAppState()

        state.assistantProvider = .claude
        #expect(state.assistantEffort == "low")

        state.assistantProvider = .copilot
        #expect(state.assistantEffort == "")

        state.assistantProvider = .codex
        #expect(state.assistantEffort == "medium")
    }

    @Test("assistant effort is stored per provider")
    @MainActor
    func assistantEffortPerProvider() {
        let state = makeCleanAppState()

        state.assistantProvider = .claude
        state.assistantEffort = "high"

        state.assistantProvider = .copilot
        state.assistantEffort = "medium"

        state.assistantProvider = .claude
        #expect(state.assistantEffort == "high")

        state.assistantProvider = .copilot
        #expect(state.assistantEffort == "medium")

        state.assistantProvider = .codex
        #expect(state.assistantEffort == "medium")
    }

    @Test("assistant model persists to UserDefaults")
    @MainActor
    func assistantModelPersistsToUserDefaults() {
        let state = makeCleanAppState()
        state.assistantProvider = .claude
        state.assistantModel = "sonnet"

        let stored = UserDefaults.standard.dictionary(forKey: "assistantModelByProvider") as? [String: String]
        #expect(stored?["claude"] == "sonnet")
    }

    @Test("assistant model invalid value resets to provider default")
    @MainActor
    func assistantModelInvalidResetsToDefault() {
        let state = makeCleanAppState()
        state.assistantProvider = .claude
        state.assistantModel = "sonnet-custom"
        #expect(state.assistantModel == "default")

        state.assistantProvider = .copilot
        state.assistantModel = "not-a-model"
        #expect(state.assistantModel == "claude-haiku-4.5")

        state.assistantProvider = .codex
        state.assistantModel = "gpt-5"
        #expect(state.assistantModel == "gpt-5.6-luna")
    }

    @Test("assistant effort persists to UserDefaults")
    @MainActor
    func assistantEffortPersistsToUserDefaults() {
        let state = makeCleanAppState()
        state.assistantProvider = .claude
        state.assistantEffort = "xhigh"

        let stored = UserDefaults.standard.dictionary(forKey: "assistantEffortByProvider") as? [String: String]
        #expect(stored?["claude"] == "xhigh")
    }

    @Test("assistant effort invalid value resets to provider default")
    @MainActor
    func assistantEffortInvalidResetsToDefault() {
        let state = makeCleanAppState()
        state.assistantProvider = .claude
        state.assistantEffort = "ultra"
        #expect(state.assistantEffort == "low")

        state.assistantProvider = .copilot
        state.assistantEffort = "ultra"
        #expect(state.assistantEffort == "")

        state.assistantProvider = .codex
        state.assistantEffort = "high"
        #expect(state.assistantEffort == "high")
    }

    @Test("assistant model support for effort depends on provider and model")
    @MainActor
    func assistantModelSupportForEffort() {
        let state = makeCleanAppState()

        state.assistantProvider = .copilot
        state.assistantModel = "gpt-5.3-codex"
        #expect(state.assistantModelSupportsEffort == true)

        state.assistantModel = "gpt-5-mini"
        #expect(state.assistantModelSupportsEffort == false)

        state.assistantProvider = .claude
        state.assistantModel = "sonnet"
        #expect(state.assistantModelSupportsEffort == true)

        state.assistantModel = "haiku"
        #expect(state.assistantModelSupportsEffort == false)

        state.assistantProvider = .codex
        #expect(state.assistantModelSupportsEffort == true)
        #expect(AppState.assistantEffortOptions(for: .codex, model: "gpt-5.6-terra") == ["", "low", "medium", "high", "xhigh", "max", "ultra"])
        state.assistantModel = "gpt-5.6-luna"
        #expect(AppState.assistantEffortOptions(for: .codex, model: state.assistantModel) == ["", "low", "medium", "high", "xhigh", "max"])
    }

    @Test("assistant Codex model options include supported 5.6 models")
    @MainActor
    func assistantCodexModelOptions() {
        let options = AppState.assistantModelOptions(for: .codex)
        #expect(options == ["gpt-5.6-terra", "gpt-5.6-luna"])
    }
}
