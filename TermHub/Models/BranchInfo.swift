import Foundation

struct BranchInfo: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let lastCommitDate: Date
    let isCurrentBranch: Bool
    let hasActiveSession: Bool

    var prefix: String? {
        guard let slashIndex = name.lastIndex(of: "/") else { return nil }
        return String(name[...slashIndex])
    }

    var leafName: String {
        guard let slashIndex = name.lastIndex(of: "/") else { return name }
        return String(name[name.index(after: slashIndex)...])
    }

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastCommitDate, relativeTo: Date())
    }
}
