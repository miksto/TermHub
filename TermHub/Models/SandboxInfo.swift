import Foundation

struct SandboxInfo: Sendable, Equatable, Decodable {
    let name: String
    let agent: String
    let status: String
    let workspaces: [String]

    var isRunning: Bool { status == "running" }
    var isStopped: Bool { status == "stopped" }

    enum CodingKeys: String, CodingKey {
        case name, agent, status, workspaces
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        agent = try container.decodeIfPresent(String.self, forKey: .agent) ?? ""
        status = try container.decode(String.self, forKey: .status)
        workspaces = try container.decodeIfPresent([String].self, forKey: .workspaces) ?? []
    }

    init(name: String, agent: String, status: String, workspaces: [String]) {
        self.name = name
        self.agent = agent
        self.status = status
        self.workspaces = workspaces
    }
}

struct SandboxListResponse: Decodable {
    let vms: [SandboxInfo]
}
