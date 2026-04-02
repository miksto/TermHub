import Foundation
import Testing
@testable import TermHub

@Suite("FolderGroup Tests")
struct FolderGroupTests {

    // MARK: - Model Tests

    @Test("FolderGroup defaults")
    func defaults() {
        let group = FolderGroup(name: "My Group")
        #expect(group.name == "My Group")
        #expect(group.folderIDs.isEmpty)
        #expect(group.isExpanded == true)
    }

    @Test("FolderGroup Codable round-trip")
    func codableRoundTrip() throws {
        let folderID = UUID()
        let original = FolderGroup(name: "Test", folderIDs: [folderID], isExpanded: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FolderGroup.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == "Test")
        #expect(decoded.folderIDs == [folderID])
        #expect(decoded.isExpanded == false)
    }

    @Test("SidebarItem Codable round-trip")
    func sidebarItemCodable() throws {
        let folderID = UUID()
        let groupID = UUID()
        let items: [SidebarItem] = [.folder(folderID), .group(groupID)]
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([SidebarItem].self, from: data)
        #expect(decoded == items)
    }

    @Test("SidebarItem equality")
    func sidebarItemEquality() {
        let id = UUID()
        #expect(SidebarItem.folder(id) == SidebarItem.folder(id))
        #expect(SidebarItem.group(id) == SidebarItem.group(id))
        #expect(SidebarItem.folder(id) != SidebarItem.group(id))
    }

    // MARK: - AppState Group Management

    @MainActor
    private func makeCleanAppState() -> AppState {
        AppState(persistence: NullPersistence())
    }

    @Test("addGroup creates group and adds to sidebarOrder")
    @MainActor
    func addGroup() {
        let state = makeCleanAppState()
        state.addGroup(name: "Backend")
        #expect(state.groups.count == 1)
        #expect(state.groups[0].name == "Backend")
        #expect(state.sidebarOrder.contains(.group(state.groups[0].id)))
    }

    @Test("removeGroup removes group and ungroups folders")
    @MainActor
    func removeGroup() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addGroup(name: "G")
        let groupID = state.groups[0].id
        state.moveFolderToGroup(folderID: folderID, groupID: groupID)

        #expect(!state.sidebarOrder.contains(.folder(folderID)))
        state.removeGroup(id: groupID)

        #expect(state.groups.isEmpty)
        #expect(!state.sidebarOrder.contains(.group(groupID)))
        // Folder should be back in sidebarOrder
        #expect(state.sidebarOrder.contains(.folder(folderID)))
    }

    @Test("renameGroup updates group name")
    @MainActor
    func renameGroup() {
        let state = makeCleanAppState()
        state.addGroup(name: "Old")
        let id = state.groups[0].id
        state.renameGroup(id: id, name: "New")
        #expect(state.groups[0].name == "New")
    }

    @Test("setGroupExpanded toggles expansion")
    @MainActor
    func setGroupExpanded() {
        let state = makeCleanAppState()
        state.addGroup(name: "G")
        let id = state.groups[0].id
        #expect(state.groups[0].isExpanded == true)

        state.setGroupExpanded(id: id, isExpanded: false)
        #expect(state.groups[0].isExpanded == false)

        state.setGroupExpanded(id: id, isExpanded: true)
        #expect(state.groups[0].isExpanded == true)
    }

    @Test("moveFolderToGroup moves folder from top-level to group")
    @MainActor
    func moveFolderToGroup() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addGroup(name: "G")
        let groupID = state.groups[0].id

        #expect(state.sidebarOrder.contains(.folder(folderID)))
        state.moveFolderToGroup(folderID: folderID, groupID: groupID)

        #expect(!state.sidebarOrder.contains(.folder(folderID)))
        #expect(state.groups[0].folderIDs == [folderID])
    }

    @Test("moveFolderToGroup between groups")
    @MainActor
    func moveFolderBetweenGroups() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addGroup(name: "G1")
        state.addGroup(name: "G2")
        let g1 = state.groups[0].id
        let g2 = state.groups[1].id

        state.moveFolderToGroup(folderID: folderID, groupID: g1)
        #expect(state.groups[0].folderIDs == [folderID])

        state.moveFolderToGroup(folderID: folderID, groupID: g2)
        #expect(state.groups[0].folderIDs.isEmpty)
        #expect(state.groups[1].folderIDs == [folderID])
    }

    @Test("moveFolderOutOfGroup returns folder to sidebarOrder")
    @MainActor
    func moveFolderOutOfGroup() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addGroup(name: "G")
        let groupID = state.groups[0].id

        state.moveFolderToGroup(folderID: folderID, groupID: groupID)
        state.moveFolderOutOfGroup(folderID: folderID)

        #expect(state.groups[0].folderIDs.isEmpty)
        #expect(state.sidebarOrder.contains(.folder(folderID)))
    }

    @Test("moveSidebarItem reorders top-level items")
    @MainActor
    func moveSidebarItem() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addGroup(name: "G")
        // sidebarOrder: [.folder(...), .group(...)]
        #expect(state.sidebarOrder.count == 2)

        state.moveSidebarItem(from: 1, to: 0)
        if case .group = state.sidebarOrder[0] {} else {
            Issue.record("Expected group at index 0")
        }
    }

    @Test("moveFolderWithinGroup reorders folders inside a group")
    @MainActor
    func moveFolderWithinGroup() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        state.addFolder(path: "/var")
        let f1 = state.folders[0].id
        let f2 = state.folders[1].id
        state.addGroup(name: "G")
        let gid = state.groups[0].id

        state.moveFolderToGroup(folderID: f1, groupID: gid)
        state.moveFolderToGroup(folderID: f2, groupID: gid)
        #expect(state.groups[0].folderIDs == [f1, f2])

        state.moveFolderWithinGroup(groupID: gid, from: 1, to: 0)
        #expect(state.groups[0].folderIDs == [f2, f1])
    }

    @Test("group(forFolderID:) returns correct group")
    @MainActor
    func groupForFolderID() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id

        #expect(state.group(forFolderID: folderID) == nil)

        state.addGroup(name: "G")
        let groupID = state.groups[0].id
        state.moveFolderToGroup(folderID: folderID, groupID: groupID)

        #expect(state.group(forFolderID: folderID)?.id == groupID)
    }

    @Test("removeFolder cleans up from group")
    @MainActor
    func removeFolderCleansUpGroup() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        state.addGroup(name: "G")
        let groupID = state.groups[0].id
        state.moveFolderToGroup(folderID: folderID, groupID: groupID)

        state.removeFolder(id: folderID)
        #expect(state.groups[0].folderIDs.isEmpty)
        #expect(!state.sidebarOrder.contains(.folder(folderID)))
    }

    @Test("addFolder adds to sidebarOrder")
    @MainActor
    func addFolderAddsSidebarOrder() {
        let state = makeCleanAppState()
        state.addFolder(path: "/tmp")
        let folderID = state.folders[0].id
        #expect(state.sidebarOrder == [.folder(folderID)])
    }

    // MARK: - Persistence

    @Test("PersistedState without groups decodes with nil")
    func backwardCompatibility() throws {
        let json = """
        {
            "folders": [],
            "sessions": []
        }
        """
        let data = Data(json.utf8)
        let state = try JSONDecoder().decode(PersistedState.self, from: data)
        #expect(state.groups == nil)
        #expect(state.sidebarOrder == nil)
    }

    @Test("PersistedState with groups round-trips")
    func persistedStateRoundTrip() throws {
        let groupID = UUID()
        let folderID = UUID()
        let group = FolderGroup(id: groupID, name: "Test Group", folderIDs: [folderID])
        let order: [SidebarItem] = [.group(groupID)]
        let state = PersistedState(
            folders: [],
            sessions: [],
            groups: [group],
            sidebarOrder: order
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        #expect(decoded.groups?.count == 1)
        #expect(decoded.groups?[0].name == "Test Group")
        #expect(decoded.sidebarOrder == order)
    }

    @Test("Migration: empty sidebarOrder initialized from folders")
    @MainActor
    func migrationFromExistingFolders() throws {
        let f1 = ManagedFolder(path: "/tmp", isGitRepo: false)
        let f2 = ManagedFolder(path: "/var", isGitRepo: false)
        let s1 = TerminalSession(folderID: f1.id, title: "tmp", workingDirectory: "/tmp")
        let s2 = TerminalSession(folderID: f2.id, title: "var", workingDirectory: "/var")
        var mf1 = f1
        mf1.sessionIDs = [s1.id]
        var mf2 = f2
        mf2.sessionIDs = [s2.id]

        let persisted = PersistedState(
            folders: [mf1, mf2],
            sessions: [s1, s2],
            groups: nil,
            sidebarOrder: nil
        )

        let persistence = InMemoryPersistence(state: persisted)
        let state = AppState(persistence: persistence)

        #expect(state.sidebarOrder == [.folder(mf1.id), .folder(mf2.id)])
        #expect(state.groups.isEmpty)
    }
}

/// In-memory persistence for migration testing.
private final class InMemoryPersistence: StatePersistence, @unchecked Sendable {
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
