import Foundation

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
            sessionMRUOrder: result.sessionMRUOrder
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
        PersistedState(folders: [], sessions: [], selectedSessionID: nil, sessionMRUOrder: nil)
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
    ) throws -> (folders: [ManagedFolder], sessions: [TerminalSession], selectedSessionID: UUID?, sessionMRUOrder: [UUID]) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (folders: [], sessions: [], selectedSessionID: nil, sessionMRUOrder: [])
        }
        do {
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            return (folders: state.folders, sessions: state.sessions, selectedSessionID: state.selectedSessionID, sessionMRUOrder: state.sessionMRUOrder ?? [])
        } catch {
            throw PersistenceError.decodingFailed(error)
        }
    }
}
