import Foundation
import Testing
@testable import TermHub

@Suite("CommandPaletteState Tests")
struct CommandPaletteStateTests {

    @Test("initial state is root mode with empty query")
    @MainActor
    func initialState() {
        let state = CommandPaletteState()
        #expect(state.query == "")
        #expect(state.selectedIndex == 0)
        #expect(state.modeStack.count == 1)
        if case .commands = state.currentMode {} else {
            Issue.record("Expected .commands mode")
        }
    }

    @Test("pushMode adds to stack and resets query")
    @MainActor
    func pushMode() {
        let state = CommandPaletteState()
        state.query = "something"
        state.selectedIndex = 5

        state.pushMode(.folderPicker(action: .newShell))
        #expect(state.modeStack.count == 2)
        #expect(state.query == "")
        #expect(state.selectedIndex == 0)
        if case .folderPicker(.newShell) = state.currentMode {} else {
            Issue.record("Expected .folderPicker(.newShell) mode")
        }
    }

    @Test("popMode returns to previous mode")
    @MainActor
    func popMode() {
        let state = CommandPaletteState()
        state.pushMode(.folderPicker(action: .removeFolder))
        state.query = "test"

        let popped = state.popMode()
        #expect(popped == true)
        #expect(state.modeStack.count == 1)
        #expect(state.query == "")
        if case .commands = state.currentMode {} else {
            Issue.record("Expected .commands mode after pop")
        }
    }

    @Test("popMode at root returns false")
    @MainActor
    func popModeAtRoot() {
        let state = CommandPaletteState()
        let popped = state.popMode()
        #expect(popped == false)
        #expect(state.modeStack.count == 1)
    }

    @Test("reset restores initial state")
    @MainActor
    func reset() {
        let state = CommandPaletteState()
        state.pushMode(.folderPicker(action: .newShell))
        state.query = "test"
        state.selectedIndex = 3
        state.branches = ["main", "dev"]

        state.reset()
        #expect(state.query == "")
        #expect(state.selectedIndex == 0)
        #expect(state.modeStack.count == 1)
        #expect(state.branches.isEmpty)
        #expect(state.isLoadingBranches == false)
    }

    @Test("moveSelectionUp decrements index")
    @MainActor
    func moveSelectionUp() {
        let state = CommandPaletteState()
        state.selectedIndex = 3
        state.moveSelectionUp()
        #expect(state.selectedIndex == 2)
    }

    @Test("moveSelectionUp at zero stays at zero")
    @MainActor
    func moveSelectionUpAtZero() {
        let state = CommandPaletteState()
        state.selectedIndex = 0
        state.moveSelectionUp()
        #expect(state.selectedIndex == 0)
    }

    @Test("moveSelectionDown increments index")
    @MainActor
    func moveSelectionDown() {
        let state = CommandPaletteState()
        state.selectedIndex = 1
        state.moveSelectionDown(itemCount: 5)
        #expect(state.selectedIndex == 2)
    }

    @Test("moveSelectionDown at last stays at last")
    @MainActor
    func moveSelectionDownAtEnd() {
        let state = CommandPaletteState()
        state.selectedIndex = 4
        state.moveSelectionDown(itemCount: 5)
        #expect(state.selectedIndex == 4)
    }

    @Test("clampSelection reduces index when items shrink")
    @MainActor
    func clampSelection() {
        let state = CommandPaletteState()
        state.selectedIndex = 10
        state.clampSelection(itemCount: 3)
        #expect(state.selectedIndex == 2)
    }

    @Test("clampSelection sets zero when no items")
    @MainActor
    func clampSelectionEmpty() {
        let state = CommandPaletteState()
        state.selectedIndex = 5
        state.clampSelection(itemCount: 0)
        #expect(state.selectedIndex == 0)
    }

    @Test("breadcrumbs empty at root")
    @MainActor
    func breadcrumbsAtRoot() {
        let state = CommandPaletteState()
        #expect(state.breadcrumbs.isEmpty)
    }

    @Test("breadcrumbs reflect mode stack")
    @MainActor
    func breadcrumbsReflectStack() {
        let state = CommandPaletteState()
        state.pushMode(.folderPicker(action: .newShell))
        #expect(state.breadcrumbs == ["New Shell"])
    }

    @Test("root items show only actions, not sessions")
    @MainActor
    func rootItemsShowOnlyActions() {
        let appState = makeCleanAppState()
        appState.addFolder(path: "/tmp")

        let paletteState = CommandPaletteState()
        let items = paletteState.items(appState: appState) { }

        let sessionItems = items.filter { $0.id.hasPrefix("session-") }
        #expect(sessionItems.isEmpty)

        let actionItems = items.filter { $0.id.hasPrefix("action-") }
        #expect(!actionItems.isEmpty)
        #expect(actionItems.contains { $0.id == "action-go-to-session" })
    }

    @Test("session picker mode shows sessions")
    @MainActor
    func sessionPickerShowsSessions() {
        let appState = makeCleanAppState()
        appState.addFolder(path: "/tmp")

        let paletteState = CommandPaletteState()
        paletteState.pushMode(.sessionPicker)
        let items = paletteState.items(appState: appState) { }

        let sessionItems = items.filter { $0.id.hasPrefix("session-") }
        #expect(sessionItems.count == 1)
    }

    @Test("query filters items by fuzzy match")
    @MainActor
    func queryFiltersItems() {
        let appState = makeCleanAppState()
        appState.addFolder(path: "/tmp")

        let paletteState = CommandPaletteState()
        let allItems = paletteState.items(appState: appState) { }

        paletteState.query = "keyboard"
        let filtered = paletteState.items(appState: appState) { }

        #expect(filtered.count < allItems.count)
        #expect(filtered.contains { $0.title.contains("Keyboard") })
    }

    @Test("folder picker mode shows folders")
    @MainActor
    func folderPickerShowsFolders() {
        let appState = makeCleanAppState()
        appState.addFolder(path: "/tmp")

        let paletteState = CommandPaletteState()
        paletteState.pushMode(.folderPicker(action: .newShell))
        let items = paletteState.items(appState: appState) { }

        #expect(items.count == 1)
        #expect(items[0].title == "tmp")
    }

    @Test("text input mode returns empty items")
    @MainActor
    func textInputReturnsEmpty() {
        let appState = makeCleanAppState()
        let paletteState = CommandPaletteState()

        let folder = ManagedFolder(path: "/tmp")
        paletteState.pushMode(.textInput(prompt: "Name", action: .newBranch(folder: folder)))
        let items = paletteState.items(appState: appState) { }

        #expect(items.isEmpty)
    }

    // MARK: - Helpers

    @MainActor
    private func makeCleanAppState() -> AppState {
        AppState(persistence: NullPersistence())
    }
}
