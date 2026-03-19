import Foundation

struct ManagedFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var sessionIDs: [UUID]

    init(id: UUID = UUID(), name: String? = nil, path: String, sessionIDs: [UUID] = []) {
        self.id = id
        self.name = name ?? (path as NSString).lastPathComponent
        self.path = path
        self.sessionIDs = sessionIDs
    }
}
