import Foundation

enum AssistantMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case error
}

struct AssistantMessage: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var role: AssistantMessageRole
    var content: String
    var timestamp: Date

    init(
        id: UUID = UUID(),
        role: AssistantMessageRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

enum PersistenceError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed(Error)
    case fileSystemError(Error)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode state"
        case .decodingFailed(let error):
            return "Failed to decode state: \(error.localizedDescription)"
        case .fileSystemError(let error):
            return "File system error: \(error.localizedDescription)"
        }
    }
}

struct PersistedState: Codable {
    var folders: [ManagedFolder]
    var sessions: [TerminalSession]
    var selectedSessionID: UUID?
    var sessionMRUOrder: [UUID]?
    /// Per-sandbox environment variable names to forward from the host. Keyed by sandbox name.
    var sandboxEnvironmentKeys: [String: [String]]?
    var assistantMessages: [AssistantMessage]? = nil
    var assistantSessionId: UUID? = nil
    /// Assistant session IDs keyed by provider raw value (e.g. "claude", "copilot").
    var assistantSessionIdsByProvider: [String: UUID]? = nil
    /// Assistant allowed tools keyed by provider raw value (e.g. "claude", "copilot").
    var assistantAllowedToolsByProvider: [String: String]? = nil
    /// Folder groups for sidebar organization.
    var groups: [FolderGroup]? = nil
    /// Top-level sidebar ordering of groups and ungrouped folders.
    var sidebarOrder: [SidebarItem]? = nil
}

/// Abstraction over state persistence so AppState can be tested without touching disk.
protocol StatePersistence: Sendable {
    func save(state: PersistedState) throws
    func load() throws -> PersistedState
    func scheduleWrite(_ work: @escaping @Sendable () -> Void)
}

/// Production persistence: reads/writes JSON to ~/Library/Application Support/TermHub/state.json.
final class DiskPersistence: StatePersistence {
    private let writeQueue = DispatchQueue(label: "com.termhub.persistence-write")

    private var stateFileURL: URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory is unavailable")
        }
        let appDir = appSupport.appendingPathComponent("TermHub", isDirectory: true)
        return appDir.appendingPathComponent("state.json")
    }

    func save(state: PersistedState) throws {
        try PersistenceService.save(state: state, to: stateFileURL)
    }

    func load() throws -> PersistedState {
        let result = try PersistenceService.load(from: stateFileURL)
        return PersistedState(
            folders: result.folders,
            sessions: result.sessions,
            selectedSessionID: result.selectedSessionID,
            sessionMRUOrder: result.sessionMRUOrder,
            sandboxEnvironmentKeys: result.sandboxEnvironmentKeys,
            assistantMessages: result.assistantMessages,
            assistantSessionId: result.assistantSessionId,
            assistantSessionIdsByProvider: result.assistantSessionIdsByProvider,
            assistantAllowedToolsByProvider: result.assistantAllowedToolsByProvider,
            groups: result.groups,
            sidebarOrder: result.sidebarOrder
        )
    }

    func scheduleWrite(_ work: @escaping @Sendable () -> Void) {
        writeQueue.async { work() }
    }
}

/// No-op persistence for tests — never touches the file system.
final class NullPersistence: StatePersistence {
    func save(state: PersistedState) throws {}
    func load() throws -> PersistedState {
        PersistedState(
            folders: [],
            sessions: [],
            selectedSessionID: nil,
            sessionMRUOrder: nil,
            sandboxEnvironmentKeys: nil,
            assistantMessages: nil,
            assistantSessionId: nil,
            assistantSessionIdsByProvider: nil,
            assistantAllowedToolsByProvider: nil,
            groups: nil,
            sidebarOrder: nil
        )
    }
    func scheduleWrite(_ work: @escaping @Sendable () -> Void) {}
}

enum PersistenceService {
    static func save(state: PersistedState, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            throw PersistenceError.encodingFailed
        }

        let fm = FileManager.default
        let backupURL = url.appendingPathExtension("bak")
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: url, to: backupURL)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PersistenceError.fileSystemError(error)
        }
    }

    static func save(
        folders: [ManagedFolder],
        sessions: [TerminalSession],
        selectedSessionID: UUID? = nil,
        sessionMRUOrder: [UUID] = [],
        to url: URL
    ) throws {
        let state = PersistedState(folders: folders, sessions: sessions, selectedSessionID: selectedSessionID, sessionMRUOrder: sessionMRUOrder)
        try save(state: state, to: url)
    }

    static func load(
        from url: URL
    ) throws -> (
        folders: [ManagedFolder],
        sessions: [TerminalSession],
        selectedSessionID: UUID?,
        sessionMRUOrder: [UUID],
        sandboxEnvironmentKeys: [String: [String]],
        assistantMessages: [AssistantMessage],
        assistantSessionId: UUID?,
        assistantSessionIdsByProvider: [String: UUID],
        assistantAllowedToolsByProvider: [String: String],
        groups: [FolderGroup],
        sidebarOrder: [SidebarItem]
    ) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (
                folders: [],
                sessions: [],
                selectedSessionID: nil,
                sessionMRUOrder: [],
                sandboxEnvironmentKeys: [:],
                assistantMessages: [],
                assistantSessionId: nil,
                assistantSessionIdsByProvider: [:],
                assistantAllowedToolsByProvider: [:],
                groups: [],
                sidebarOrder: []
            )
        }
        do {
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            return (
                folders: state.folders,
                sessions: state.sessions,
                selectedSessionID: state.selectedSessionID,
                sessionMRUOrder: state.sessionMRUOrder ?? [],
                sandboxEnvironmentKeys: state.sandboxEnvironmentKeys ?? [:],
                assistantMessages: state.assistantMessages ?? [],
                assistantSessionId: state.assistantSessionId,
                assistantSessionIdsByProvider: state.assistantSessionIdsByProvider ?? [:],
                assistantAllowedToolsByProvider: state.assistantAllowedToolsByProvider ?? [:],
                groups: state.groups ?? [],
                sidebarOrder: state.sidebarOrder ?? []
            )
        } catch {
            throw PersistenceError.decodingFailed(error)
        }
    }
}
