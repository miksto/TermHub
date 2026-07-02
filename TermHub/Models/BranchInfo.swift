import Foundation

struct BranchInfo: Identifiable, Hashable, Sendable {
    var id: String { remoteStartPoint ?? name }
    let name: String
    let lastCommitDate: Date
    let isCurrentBranch: Bool
    let hasActiveSession: Bool
    let remoteName: String?
    let remoteStartPoint: String?

    init(
        name: String,
        lastCommitDate: Date,
        isCurrentBranch: Bool,
        hasActiveSession: Bool,
        remoteName: String? = nil,
        remoteStartPoint: String? = nil
    ) {
        self.name = name
        self.lastCommitDate = lastCommitDate
        self.isCurrentBranch = isCurrentBranch
        self.hasActiveSession = hasActiveSession
        self.remoteName = remoteName
        self.remoteStartPoint = remoteStartPoint
    }

    var isRemoteOnly: Bool {
        remoteStartPoint != nil
    }

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
