import Foundation
import Testing
@testable import TermHub

@Suite("PersistenceService Extended Tests")
struct PersistenceServiceExtendedTests {
    private func makeTempURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermHubTests-\(UUID().uuidString)", isDirectory: true)
        return tempDir.appendingPathComponent("state.json")
    }

    private func cleanup(_ url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Backup behavior

    @Test("save creates backup of existing file")
    func saveCreatesBackup() throws {
        let url = makeTempURL()
        defer { cleanup(url) }

        let folder = ManagedFolder(path: "/tmp/repo", isGitRepo: false)
        let session = TerminalSession(folderID: folder.id, title: "S1", workingDirectory: "/tmp/repo")

        // First save
        try PersistenceService.save(folders: [folder], sessions: [session], to: url)

        // Second save should create .bak
        let folder2 = ManagedFolder(path: "/tmp/repo2", isGitRepo: false)
        try PersistenceService.save(folders: [folder2], sessions: [], to: url)

        let backupURL = url.appendingPathExtension("bak")
        #expect(FileManager.default.fileExists(atPath: backupURL.path))

        // Backup should contain original data
        let backupData = try Data(contentsOf: backupURL)
        let backupState = try JSONDecoder().decode(PersistedState.self, from: backupData)
        #expect(backupState.folders.count == 1)
        #expect(backupState.folders[0].path == "/tmp/repo")
    }

    // MARK: - selectedSessionID persistence

    @Test("save and load preserves selectedSessionID")
    func selectedSessionIDPersisted() throws {
        let url = makeTempURL()
        defer { cleanup(url) }

        let folder = ManagedFolder(path: "/tmp/repo", isGitRepo: false)
        let session = TerminalSession(folderID: folder.id, title: "S1", workingDirectory: "/tmp/repo")

        try PersistenceService.save(
            folders: [folder],
            sessions: [session],
            selectedSessionID: session.id,
            to: url
        )
        let loaded = try PersistenceService.load(from: url)
        #expect(loaded.selectedSessionID == session.id)
    }

    @Test("save and load preserves nil selectedSessionID")
    func nilSelectedSessionIDPersisted() throws {
        let url = makeTempURL()
        defer { cleanup(url) }

        try PersistenceService.save(folders: [], sessions: [], selectedSessionID: nil, to: url)
        let loaded = try PersistenceService.load(from: url)
        #expect(loaded.selectedSessionID == nil)
    }

    // MARK: - MRU order persistence

    @Test("save and load preserves sessionMRUOrder")
    func mruOrderPersisted() throws {
        let url = makeTempURL()
        defer { cleanup(url) }

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        try PersistenceService.save(
            folders: [],
            sessions: [],
            sessionMRUOrder: [id1, id2, id3],
            to: url
        )
        let loaded = try PersistenceService.load(from: url)
        #expect(loaded.sessionMRUOrder == [id1, id2, id3])
    }

    @Test("load returns empty MRU order when not present in JSON")
    func mruOrderMissingInJSON() throws {
        let url = makeTempURL()
        defer { cleanup(url) }

        // Write JSON without sessionMRUOrder field
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        {"folders":[],"sessions":[]}
        """
        try Data(json.utf8).write(to: url)

        let loaded = try PersistenceService.load(from: url)
        #expect(loaded.sessionMRUOrder.isEmpty)
    }

    // MARK: - Directory creation

    @Test("save creates intermediate directories")
    func saveCreatesDirectories() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermHubTests-\(UUID().uuidString)")
            .appendingPathComponent("nested")
            .appendingPathComponent("deeply")
            .appendingPathComponent("state.json")
        defer {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            )
        }

        try PersistenceService.save(folders: [], sessions: [], to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - PersistedState Codable

    @Test("PersistedState round-trips through Codable with all fields")
    func persistedStateRoundTrip() throws {
        let folder = ManagedFolder(name: "Test", path: "/tmp/test", isGitRepo: true)
        let session = TerminalSession(
            folderID: folder.id,
            title: "Main",
            workingDirectory: "/tmp/test",
            worktreePath: "/tmp/test-wt",
            branchName: "feature/x"
        )
        let state = PersistedState(
            folders: [folder],
            sessions: [session],
            selectedSessionID: session.id,
            sessionMRUOrder: [session.id]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)

        #expect(decoded.folders.count == 1)
        #expect(decoded.sessions.count == 1)
        #expect(decoded.selectedSessionID == session.id)
        #expect(decoded.sessionMRUOrder == [session.id])
    }

    // MARK: - Error types

    @Test("PersistenceError descriptions are non-empty")
    func errorDescriptions() {
        let errors: [PersistenceError] = [
            .encodingFailed,
            .decodingFailed(NSError(domain: "test", code: 0)),
            .fileSystemError(NSError(domain: "test", code: 0)),
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    // MARK: - save with PersistedState directly

    @Test("save with PersistedState struct works")
    func saveWithPersistedState() throws {
        let url = makeTempURL()
        defer { cleanup(url) }

        let state = PersistedState(
            folders: [ManagedFolder(path: "/tmp/r", isGitRepo: false)],
            sessions: [],
            selectedSessionID: nil,
            sessionMRUOrder: nil
        )
        try PersistenceService.save(state: state, to: url)

        let loaded = try PersistenceService.load(from: url)
        #expect(loaded.folders.count == 1)
    }
}
