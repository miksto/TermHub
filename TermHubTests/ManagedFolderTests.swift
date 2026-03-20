import Foundation
import Testing
@testable import TermHub

@Suite("ManagedFolder Tests")
struct ManagedFolderTests {
    @Test("name is derived from path last component")
    func nameFromPath() {
        let folder = ManagedFolder(path: "/Users/dev/my-repo")
        #expect(folder.name == "my-repo")
    }

    @Test("name from deeply nested path")
    func nameFromDeepPath() {
        let folder = ManagedFolder(path: "/Users/dev/projects/swift/cool-project")
        #expect(folder.name == "cool-project")
    }

    @Test("explicit name overrides derived name")
    func explicitName() {
        let folder = ManagedFolder(name: "Custom Name", path: "/Users/dev/repo")
        #expect(folder.name == "Custom Name")
    }

    @Test("sessionIDs defaults to empty array")
    func emptySessionIDs() {
        let folder = ManagedFolder(path: "/tmp/test")
        #expect(folder.sessionIDs.isEmpty)
    }

    @Test("isGitRepo can be set explicitly")
    func explicitIsGitRepo() {
        let folder = ManagedFolder(path: "/tmp/test", isGitRepo: true)
        #expect(folder.isGitRepo == true)

        let folder2 = ManagedFolder(path: "/tmp/test2", isGitRepo: false)
        #expect(folder2.isGitRepo == false)
    }

    @Test("pathExists returns false for non-existent path")
    func pathExistsNonExistent() {
        let folder = ManagedFolder(path: "/nonexistent/path/that/does/not/exist", isGitRepo: false)
        #expect(folder.pathExists == false)
    }

    @Test("pathExists returns true for existing path")
    func pathExistsExistent() {
        let folder = ManagedFolder(path: "/tmp", isGitRepo: false)
        #expect(folder.pathExists == true)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let sessionID = UUID()
        let original = ManagedFolder(
            name: "Test Folder",
            path: "/Users/dev/test",
            sessionIDs: [sessionID],
            isGitRepo: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ManagedFolder.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.path == original.path)
        #expect(decoded.sessionIDs == original.sessionIDs)
        #expect(decoded.isGitRepo == original.isGitRepo)
    }
}
