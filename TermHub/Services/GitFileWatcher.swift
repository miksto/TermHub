import Foundation

/// Watches `.git` directories for filesystem changes using FSEvents
/// and invokes a callback when modifications are detected.
final class GitFileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.termhub.git-file-watcher")
    private var onChange: (@Sendable () -> Void)?
    private var watchedPaths: [String] = []

    /// Debounce interval to coalesce rapid filesystem events.
    private static let debounceInterval: TimeInterval = 0.5
    private var debounceWorkItem: DispatchWorkItem?

    func start(paths: [String], onChange: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            let gitPaths = paths.compactMap { self.gitDirPath(for: $0) }
            guard !gitPaths.isEmpty else { return }

            // Skip if already watching the same paths.
            if gitPaths == self.watchedPaths, self.stream != nil {
                return
            }

            self.stop()
            self.onChange = onChange
            self.watchedPaths = gitPaths

            var context = FSEventStreamContext()
            context.info = Unmanaged.passUnretained(self).toOpaque()

            let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<GitFileWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleEvent()
            }

            guard let stream = FSEventStreamCreate(
                nil,
                callback,
                &context,
                gitPaths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.3,
                UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
            ) else { return }

            self.stream = stream
            FSEventStreamSetDispatchQueue(stream, self.queue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        // Must already be on `queue` or called during deinit.
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        watchedPaths = []
    }

    deinit {
        // FSEventStream cleanup is not thread-bound, safe from deinit.
        debounceWorkItem?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: - Private

    private func handleEvent() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    private func gitDirPath(for repoPath: String) -> String? {
        let dotGit = (repoPath as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDir) {
            if isDir.boolValue {
                return dotGit
            }
            // Worktree: .git is a file containing "gitdir: <path>"
            if let content = try? String(contentsOfFile: dotGit, encoding: .utf8),
               content.hasPrefix("gitdir: ")
            {
                let gitdir = content.dropFirst("gitdir: ".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if gitdir.hasPrefix("/") {
                    return gitdir
                }
                // Relative path — resolve against repo path.
                return (repoPath as NSString).appendingPathComponent(gitdir)
            }
        }
        return nil
    }
}
