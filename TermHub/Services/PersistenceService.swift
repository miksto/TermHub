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

enum PersistenceService {
    /// Serial queue for background file I/O to avoid concurrent writes.
    static let writeQueue = DispatchQueue(label: "com.termhub.persistence-write")


    static var defaultStateFileURL: URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory is unavailable")
        }
        let appDir = appSupport.appendingPathComponent("TermHub", isDirectory: true)
        return appDir.appendingPathComponent("state.json")
    }

    static func save(state: PersistedState, to url: URL? = nil) throws {
        let fileURL = url ?? defaultStateFileURL
        let dir = fileURL.deletingLastPathComponent()
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
        let backupURL = fileURL.appendingPathExtension("bak")
        if fm.fileExists(atPath: fileURL.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: fileURL, to: backupURL)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PersistenceError.fileSystemError(error)
        }
    }

    static func save(
        folders: [ManagedFolder],
        sessions: [TerminalSession],
        selectedSessionID: UUID? = nil,
        sessionMRUOrder: [UUID] = [],
        to url: URL? = nil
    ) throws {
        let state = PersistedState(folders: folders, sessions: sessions, selectedSessionID: selectedSessionID, sessionMRUOrder: sessionMRUOrder)
        try save(state: state, to: url)
    }

    static func load(
        from url: URL? = nil
    ) throws -> (folders: [ManagedFolder], sessions: [TerminalSession], selectedSessionID: UUID?, sessionMRUOrder: [UUID]) {
        let fileURL = url ?? defaultStateFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return (folders: [], sessions: [], selectedSessionID: nil, sessionMRUOrder: [])
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            return (folders: state.folders, sessions: state.sessions, selectedSessionID: state.selectedSessionID, sessionMRUOrder: state.sessionMRUOrder ?? [])
        } catch {
            throw PersistenceError.decodingFailed(error)
        }
    }
}
