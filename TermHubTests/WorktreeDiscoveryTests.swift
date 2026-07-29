import Foundation
import Testing
@testable import TermHub

@Suite("Worktree Discovery Tests", .serialized)
struct WorktreeDiscoveryTests {
    private enum TestError: Error {
        case failed
    }

    private final class LockedBox<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func read() -> Value {
            lock.withLock { value }
        }

        func update(_ body: (inout Value) -> Void) {
            lock.withLock { body(&value) }
        }
    }

    private struct TestPaths {
        let root: String
        let child: String
    }

    private func makePaths() throws -> TestPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("termhub-worktree-tests-\(UUID().uuidString)")
        let child = root.appendingPathComponent("feature")
        try FileManager.default.createDirectory(
            at: child,
            withIntermediateDirectories: true
        )
        return TestPaths(root: root.path, child: child.path)
    }

    private func worktree(folderID: UUID, path: String, branch: String = "feature/test") -> GitWorktree {
        GitWorktree(
            folderID: folderID,
            path: path,
            normalizedPath: GitWorktree.normalizePath(path),
            head: "abcdef0123456789",
            branch: branch,
            isDetached: false,
            isBare: false,
            isLocked: false,
            lockReason: nil,
            isPrunable: false,
            prunableReason: nil
        )
    }

    @MainActor
    private func waitForDiscovery(_ state: AppState, folderID: UUID) async {
        for _ in 0..<10_000 {
            if !state.worktreeDiscoveryInProgress.contains(folderID) {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for worktree discovery")
    }

    @Test("external worktree appears without a session and managed checkout is excluded")
    @MainActor
    func externalWorktreeAppears() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(atPath: paths.root) }
        let folder = ManagedFolder(path: paths.root, isGitRepo: true)
        let records = [
            worktree(folderID: folder.id, path: paths.root, branch: "main"),
            worktree(folderID: folder.id, path: paths.child),
        ]
        let state = AppState(
            persistence: NullPersistence(),
            worktreeDiscoveryService: WorktreeDiscoveryService(
                listWorktrees: { _, _ in records },
                liveTmuxSessionNames: { [] }
            )
        )
        state.folders = [folder]

        state.refreshWorktrees()
        await waitForDiscovery(state, folderID: folder.id)

        #expect(state.worktrees(for: folder.id).map(\.path) == [paths.child])
        #expect(state.sessionsForWorktree(folderID: folder.id, path: paths.child).isEmpty)
        #expect(state.trackedGitPaths().contains(paths.child))

        let server = IPCServer(appState: state)
        let listRequest = try JSONEncoder().encode(IPCRequest(
            action: "listWorktrees",
            params: ["folderId": .string(folder.id.uuidString)]
        ))
        let listResponse = await server.handleRequest(data: listRequest)
        guard case .array(let listedWorktrees) = listResponse.data,
              case .object(let listed) = listedWorktrees.first else {
            Issue.record("Expected a discovered worktree from listWorktrees")
            return
        }
        #expect(listed["path"]?.stringValue == paths.child)
        #expect(listed["attachedSessionIDs"]?.arrayValue?.isEmpty == true)

        let overviewRequest = try JSONEncoder().encode(IPCRequest(
            action: "getWorkspaceOverview",
            params: nil
        ))
        let overviewResponse = await server.handleRequest(data: overviewRequest)
        #expect(overviewResponse.data?.objectValue?["worktrees"]?.arrayValue?.count == 1)
    }

    @Test("sessions group by normalized discovered worktree path")
    @MainActor
    func sessionsGroupByNormalizedPath() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(atPath: paths.root) }
        let folder = ManagedFolder(path: paths.root, isGitRepo: true)
        let record = worktree(folderID: folder.id, path: paths.child)
        let state = AppState(
            persistence: NullPersistence(),
            worktreeDiscoveryService: WorktreeDiscoveryService(
                listWorktrees: { _, _ in [record] },
                liveTmuxSessionNames: { [] }
            )
        )
        state.folders = [folder]
        state.addSession(
            folderID: folder.id,
            title: "Feature",
            cwd: paths.child + "/.",
            worktreePath: paths.child + "/.",
            branchName: "feature/test"
        )

        await waitForDiscovery(state, folderID: folder.id)

        #expect(state.sessionsForWorktree(folderID: folder.id, path: paths.child).count == 1)
        #expect(state.missingWorktreeSessionGroups(for: folder.id).isEmpty)
    }

    @Test("failed refresh retains the previous successful inventory")
    @MainActor
    func failedRefreshRetainsInventory() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(atPath: paths.root) }
        let folder = ManagedFolder(path: paths.root, isGitRepo: true)
        let result = LockedBox<Result<[GitWorktree], Error>>(
            .success([worktree(folderID: folder.id, path: paths.child)])
        )
        let state = AppState(
            persistence: NullPersistence(),
            worktreeDiscoveryService: WorktreeDiscoveryService(
                listWorktrees: { _, _ in try result.read().get() },
                liveTmuxSessionNames: { [] }
            )
        )
        state.folders = [folder]

        state.refreshWorktrees()
        await waitForDiscovery(state, folderID: folder.id)
        result.update { $0 = .failure(TestError.failed) }
        state.refreshWorktrees()
        await waitForDiscovery(state, folderID: folder.id)

        #expect(state.worktrees(for: folder.id).map(\.path) == [paths.child])
        #expect(state.worktreeDiscoveryErrors[folder.id] != nil)
    }

    @Test("missing worktree retains a live tmux session")
    @MainActor
    func missingWorktreeRetainsLiveSession() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(atPath: paths.root) }
        let missingPath = (paths.root as NSString).appendingPathComponent("removed")
        let folder = ManagedFolder(path: paths.root, isGitRepo: true)
        let session = TerminalSession(
            folderID: folder.id,
            title: "Missing",
            workingDirectory: missingPath,
            worktreePath: missingPath,
            branchName: "feature/missing"
        )
        var folderWithSession = folder
        folderWithSession.sessionIDs = [session.id]
        let state = AppState(
            persistence: NullPersistence(),
            worktreeDiscoveryService: WorktreeDiscoveryService(
                listWorktrees: { _, _ in [] },
                liveTmuxSessionNames: { [session.tmuxSessionName] }
            )
        )
        state.folders = [folderWithSession]
        state.sessions = [session]

        state.refreshWorktrees()
        await waitForDiscovery(state, folderID: folder.id)

        #expect(state.sessions.map(\.id) == [session.id])
        #expect(state.missingWorktreeSessionGroups(for: folder.id).first?.sessionIDs == [session.id])
    }

    @Test("missing worktree prunes a session whose tmux endpoint is gone")
    @MainActor
    func missingWorktreePrunesDeadSession() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(atPath: paths.root) }
        let missingPath = (paths.root as NSString).appendingPathComponent("removed")
        let folder = ManagedFolder(path: paths.root, isGitRepo: true)
        let session = TerminalSession(
            folderID: folder.id,
            title: "Stale",
            workingDirectory: missingPath,
            worktreePath: missingPath
        )
        var folderWithSession = folder
        folderWithSession.sessionIDs = [session.id]
        let state = AppState(
            persistence: NullPersistence(),
            worktreeDiscoveryService: WorktreeDiscoveryService(
                listWorktrees: { _, _ in [] },
                liveTmuxSessionNames: { [] }
            )
        )
        state.folders = [folderWithSession]
        state.sessions = [session]

        state.refreshWorktrees()
        await waitForDiscovery(state, folderID: folder.id)

        #expect(state.sessions.isEmpty)
        #expect(state.folders[0].sessionIDs.isEmpty)
        #expect(state.missingWorktreeSessionGroups(for: folder.id).isEmpty)
    }

    @Test("prunable, bare, nonexistent, and duplicate records are not active")
    @MainActor
    func inactiveRecordsAreFiltered() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(atPath: paths.root) }
        let folderID = UUID()
        let active = worktree(folderID: folderID, path: paths.child, branch: "zeta")
        let duplicate = worktree(folderID: folderID, path: paths.child + "/.", branch: "alpha")
        let nonexistent = worktree(
            folderID: folderID,
            path: (paths.root as NSString).appendingPathComponent("gone")
        )
        let prunable = GitWorktree(
            folderID: folderID,
            path: paths.child,
            normalizedPath: active.normalizedPath,
            head: "1234567",
            branch: "prunable",
            isDetached: false,
            isBare: false,
            isLocked: false,
            lockReason: nil,
            isPrunable: true,
            prunableReason: "gone"
        )
        let bare = GitWorktree(
            folderID: folderID,
            path: paths.child,
            normalizedPath: active.normalizedPath,
            head: "1234567",
            branch: nil,
            isDetached: false,
            isBare: true,
            isLocked: false,
            lockReason: nil,
            isPrunable: false,
            prunableReason: nil
        )

        let filtered = AppState.activeDiscoveredWorktrees(
            [active, duplicate, nonexistent, prunable, bare],
            normalizedFolderPath: GitWorktree.normalizePath(paths.root)
        )

        #expect(filtered == [active])
    }
}
