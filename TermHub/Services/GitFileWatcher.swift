import Foundation

/// Watches repository and worktree directories for filesystem changes using FSEvents
/// and invokes a callback when modifications are detected.
final class GitFileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.termhub.git-file-watcher")
    private var onChange: (@Sendable ([String]) -> Void)?
    private var watchedPaths: [String] = []

    /// Debounce interval to coalesce rapid filesystem events.
    private static let debounceInterval: TimeInterval = 0.5
    private var debounceWorkItem: DispatchWorkItem?

    private var pendingChangedPaths: Set<String> = []

    func start(paths: [String], onChange: @escaping @Sendable ([String]) -> Void) {
        queue.async { [self] in
            let sorted = paths.sorted()
            guard !sorted.isEmpty else {
                self.stop()
                self.onChange = nil
                return
            }

            // Skip if already watching the same paths.
            if sorted == self.watchedPaths, self.stream != nil {
                return
            }

            self.stop()
            self.onChange = onChange
            self.watchedPaths = sorted
            self.pendingChangedPaths.removeAll()

            var context = FSEventStreamContext()
            context.info = Unmanaged.passUnretained(self).toOpaque()

            let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<GitFileWatcher>.fromOpaque(info).takeUnretainedValue()
                let array = unsafeBitCast(eventPaths, to: NSArray.self)
                let paths = array.compactMap { $0 as? String }
                watcher.handleEvent(paths: Array(paths.prefix(Int(numEvents))))
            }

            guard let stream = FSEventStreamCreate(
                nil,
                callback,
                &context,
                sorted as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.3,
                UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
            ) else {
                print("[TermHub] Failed to create Git filesystem watcher for: \(sorted.joined(separator: ", "))")
                return
            }

            self.stream = stream
            FSEventStreamSetDispatchQueue(stream, self.queue)
            if !FSEventStreamStart(stream) {
                print("[TermHub] Failed to start Git filesystem watcher for: \(sorted.joined(separator: ", "))")
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
        }
    }

    func stop() {
        // Must already be on `queue` or called during deinit.
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingChangedPaths.removeAll()
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

    private func handleEvent(paths: [String]) {
        // FSEvents may report thousands of paths for a checkout or a worktree
        // deletion. Consumers only need to know which watched roots changed, so
        // compact the batch on the watcher queue before crossing to the main actor.
        for path in paths {
            let matchingRoots = watchedPaths.filter {
                path == $0 || path.hasPrefix($0 + "/")
            }
            if matchingRoots.isEmpty {
                pendingChangedPaths.insert(path)
            } else {
                pendingChangedPaths.formUnion(matchingRoots)
            }
        }
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let changedPaths = Array(self.pendingChangedPaths)
            self.pendingChangedPaths.removeAll()
            self.onChange?(changedPaths)
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }
}
