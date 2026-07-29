import Foundation

struct GitWorktree: Identifiable, Equatable, Sendable {
    let folderID: UUID
    let path: String
    let normalizedPath: String
    let head: String
    let branch: String?
    let isDetached: Bool
    let isBare: Bool
    let isLocked: Bool
    let lockReason: String?
    let isPrunable: Bool
    let prunableReason: String?

    var id: String { "\(folderID.uuidString):\(normalizedPath)" }

    var displayName: String {
        if let branch {
            return branch
        }
        let shortHead = String(head.prefix(7))
        return "Detached @ \(shortHead)"
    }

    static func normalizePath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        var normalized = (expanded as NSString).standardizingPath

        if normalized.count > 1 {
            while normalized.hasSuffix("/") {
                normalized.removeLast()
            }
        }

        if FileManager.default.fileExists(atPath: normalized) {
            normalized = URL(fileURLWithPath: normalized)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path
        }
        return normalized
    }
}

struct MissingWorktreeSessionGroup: Identifiable, Equatable, Sendable {
    let folderID: UUID
    let path: String
    let normalizedPath: String
    let branchName: String?
    let sessionIDs: [UUID]

    var id: String { "\(folderID.uuidString):missing:\(normalizedPath)" }
    var displayName: String { branchName ?? (path as NSString).lastPathComponent }
}
