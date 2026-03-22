import Foundation

enum DiffLineType: Sendable, Equatable {
    case context
    case added
    case removed
}

struct DiffLine: Sendable, Identifiable {
    let id = UUID()
    let type: DiffLineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

struct DiffHunk: Sendable, Identifiable {
    let id = UUID()
    let header: String
    let oldStart: Int
    let newStart: Int
    let lines: [DiffLine]
}

struct DiffFile: Sendable, Identifiable {
    let id = UUID()
    let oldPath: String
    let newPath: String
    let isBinary: Bool
    let hunks: [DiffHunk]

    var linesAdded: Int {
        hunks.flatMap(\.lines).filter { $0.type == .added }.count
    }

    var linesDeleted: Int {
        hunks.flatMap(\.lines).filter { $0.type == .removed }.count
    }

    var displayPath: String {
        if oldPath == newPath || oldPath == "/dev/null" {
            return newPath
        } else if newPath == "/dev/null" {
            return oldPath
        } else {
            return "\(oldPath) → \(newPath)"
        }
    }
}

struct GitDiff: Sendable, Equatable {
    let files: [DiffFile]

    static let empty = GitDiff(files: [])

    static func == (lhs: GitDiff, rhs: GitDiff) -> Bool {
        lhs.files.map(\.id) == rhs.files.map(\.id)
    }
}
