import Foundation

enum DiffLineType: Sendable, Equatable {
    case context
    case added
    case removed
}

struct DiffLine: Sendable, Identifiable, Equatable {
    let id = UUID()
    let type: DiffLineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    static func == (lhs: DiffLine, rhs: DiffLine) -> Bool {
        lhs.type == rhs.type
            && lhs.content == rhs.content
            && lhs.oldLineNumber == rhs.oldLineNumber
            && lhs.newLineNumber == rhs.newLineNumber
    }
}

struct DiffHunk: Sendable, Identifiable, Equatable {
    let id = UUID()
    let header: String
    let oldStart: Int
    let newStart: Int
    let lines: [DiffLine]

    static func == (lhs: DiffHunk, rhs: DiffHunk) -> Bool {
        lhs.header == rhs.header
            && lhs.oldStart == rhs.oldStart
            && lhs.newStart == rhs.newStart
            && lhs.lines == rhs.lines
    }
}

struct DiffFile: Sendable, Identifiable, Equatable {
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

    static func == (lhs: DiffFile, rhs: DiffFile) -> Bool {
        lhs.oldPath == rhs.oldPath
            && lhs.newPath == rhs.newPath
            && lhs.isBinary == rhs.isBinary
            && lhs.hunks == rhs.hunks
    }
}

struct GitDiff: Sendable, Equatable {
    let files: [DiffFile]

    static let empty = GitDiff(files: [])
}
