import Foundation

struct GitStatus: Equatable, Sendable {
    let linesAdded: Int
    let linesDeleted: Int
    let ahead: Int
    let behind: Int
    let currentBranch: String?

    var isDirty: Bool { linesAdded > 0 || linesDeleted > 0 }

    static let clean = GitStatus(linesAdded: 0, linesDeleted: 0, ahead: 0, behind: 0, currentBranch: nil)
}
