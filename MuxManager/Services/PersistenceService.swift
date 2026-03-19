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

private struct PersistedState: Codable {
    var folders: [ManagedFolder]
    var sessions: [TerminalSession]
}

enum PersistenceService {
    private static var stateFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("MuxManager", isDirectory: true)
        return appDir.appendingPathComponent("state.json")
    }

    static func save(folders: [ManagedFolder], sessions: [TerminalSession]) throws {
        let dir = stateFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let state = PersistedState(folders: folders, sessions: sessions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(state) else {
            throw PersistenceError.encodingFailed
        }
        do {
            try data.write(to: stateFileURL, options: .atomic)
        } catch {
            throw PersistenceError.fileSystemError(error)
        }
    }

    static func load() throws -> (folders: [ManagedFolder], sessions: [TerminalSession]) {
        let url = stateFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (folders: [], sessions: [])
        }
        do {
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            return (folders: state.folders, sessions: state.sessions)
        } catch {
            throw PersistenceError.decodingFailed(error)
        }
    }
}
