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
}

enum PersistenceService {
    static var defaultStateFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("TermHub", isDirectory: true)
        return appDir.appendingPathComponent("state.json")
    }

    static func save(
        folders: [ManagedFolder],
        sessions: [TerminalSession],
        to url: URL? = nil
    ) throws {
        let fileURL = url ?? defaultStateFileURL
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let state = PersistedState(folders: folders, sessions: sessions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            throw PersistenceError.encodingFailed
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PersistenceError.fileSystemError(error)
        }
    }

    static func load(
        from url: URL? = nil
    ) throws -> (folders: [ManagedFolder], sessions: [TerminalSession]) {
        let fileURL = url ?? defaultStateFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return (folders: [], sessions: [])
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            return (folders: state.folders, sessions: state.sessions)
        } catch {
            throw PersistenceError.decodingFailed(error)
        }
    }
}
