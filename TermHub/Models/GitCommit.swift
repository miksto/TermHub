import Foundation

struct GitCommit: Identifiable, Equatable, Sendable {
    let hash: String
    let authorName: String
    let authoredDate: Date
    let message: String

    var id: String { hash }

    var shortHash: String {
        String(hash.prefix(7))
    }

    /// The commit message as displayed in the history list.
    /// Keeping this presentation rule on the model lets the UI retain the full
    /// message for accessibility and future copy/detail actions.
    var messagePreview: String {
        message
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(5)
            .joined(separator: "\n")
    }
}

enum GitCommitHistory: Equatable, Sendable {
    case idle
    case unavailable(String)
    case loaded([GitCommit])
    case failed(String)
}
