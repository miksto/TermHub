import Foundation
import Testing
@testable import TermHub

@Suite("PersistenceService Tests")
struct PersistenceServiceTests {
    private func makeTempURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermHubTests-\(UUID().uuidString)", isDirectory: true)
        return tempDir.appendingPathComponent("state.json")
    }

    private func cleanup(_ url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("save and load round-trip")
    func saveLoadRoundTrip() throws {
        let url = makeTempURL()
        defer { cleanup(url) }

        let folder = ManagedFolder(name: "TestRepo", path: "/tmp/test-repo", isGitRepo: false)
        let session = TerminalSession(
            folderID: folder.id,
            title: "Main",
            workingDirectory: "/tmp/test-repo"
        )

        try PersistenceService.save(folders: [folder], sessions: [session], to: url)
        let loaded = try PersistenceService.load(from: url)

        #expect(loaded.folders.count == 1)
        #expect(loaded.sessions.count == 1)
        #expect(loaded.folders[0].id == folder.id)
        #expect(loaded.folders[0].name == "TestRepo")
        #expect(loaded.sessions[0].id == session.id)
        #expect(loaded.sessions[0].tmuxSessionName == session.tmuxSessionName)
    }

    @Test("load from empty state returns empty arrays")
    func loadEmptyState() throws {
        let url = makeTempURL()
        defer { cleanup(url) }

        // File does not exist yet
        let loaded = try PersistenceService.load(from: url)

        #expect(loaded.folders.isEmpty)
        #expect(loaded.sessions.isEmpty)
    }

    @Test("corrupted file throws decodingFailed")
    func corruptedFile() throws {
        let url = makeTempURL()
        defer { cleanup(url) }

        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: url)

        #expect(throws: PersistenceError.self) {
            try PersistenceService.load(from: url)
        }
    }

    @Test("save multiple folders and sessions")
    func multipleFoldersAndSessions() throws {
        let url = makeTempURL()
        defer { cleanup(url) }

        let folder1 = ManagedFolder(path: "/tmp/repo1", isGitRepo: false)
        let folder2 = ManagedFolder(path: "/tmp/repo2", isGitRepo: false)
        let session1 = TerminalSession(folderID: folder1.id, title: "S1", workingDirectory: "/tmp/repo1")
        let session2 = TerminalSession(
            folderID: folder2.id,
            title: "S2",
            workingDirectory: "/tmp/repo2",
            worktreePath: "/tmp/repo2-feature",
            branchName: "feature/x"
        )

        try PersistenceService.save(folders: [folder1, folder2], sessions: [session1, session2], to: url)
        let loaded = try PersistenceService.load(from: url)

        #expect(loaded.folders.count == 2)
        #expect(loaded.sessions.count == 2)
        #expect(loaded.sessions[1].branchName == "feature/x")
        #expect(loaded.sessions[1].worktreePath == "/tmp/repo2-feature")
    }
}
