import Foundation

struct GitStatus: Equatable, Sendable {
    let isDirty: Bool
    let ahead: Int
    let behind: Int

    static let clean = GitStatus(isDirty: false, ahead: 0, behind: 0)
}
