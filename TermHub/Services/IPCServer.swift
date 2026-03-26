import Foundation
import Network

@MainActor
final class IPCServer {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        // Ensure the Application Support directory exists
        let socketPath = IPCProtocol.socketPath
        let dir = (socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Remove stale socket file
        try? FileManager.default.removeItem(atPath: socketPath)

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)

        do {
            listener = try NWListener(using: params)
        } catch {
            print("[TermHub IPC] Failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[TermHub IPC] Server listening on \(socketPath)")
            case .failed(let error):
                print("[TermHub IPC] Server failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        try? FileManager.default.removeItem(atPath: IPCProtocol.socketPath)
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                Task { @MainActor in
                    self?.connections.removeAll { $0 === connection }
                }
            }
        }

        connection.start(queue: .main)
        receiveMessage(on: connection)
    }

    private func receiveMessage(on connection: NWConnection) {
        // Protocol: 4-byte big-endian length prefix, then JSON payload
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, let data, data.count == 4 else {
                if let error, case NWError.posix(let code) = error, code == .ECANCELED {
                    return
                }
                connection.cancel()
                return
            }

            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 10_000_000 else {
                connection.cancel()
                return
            }

            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] payload, _, _, error in
                guard let self, let payload else {
                    connection.cancel()
                    return
                }

                Task { @MainActor in
                    let response = await self.handleRequest(data: payload)
                    self.sendResponse(response, on: connection)
                }
            }
        }
    }

    private func sendResponse(_ response: IPCResponse, on connection: NWConnection) {
        guard let jsonData = try? JSONEncoder().encode(response) else {
            connection.cancel()
            return
        }

        var length = UInt32(jsonData.count).bigEndian
        var frameData = Data(bytes: &length, count: 4)
        frameData.append(jsonData)

        connection.send(content: frameData, completion: .contentProcessed { [weak self] error in
            if error != nil {
                connection.cancel()
            } else {
                Task { @MainActor in
                    self?.receiveMessage(on: connection)
                }
            }
        })
    }

    func handleRequest(data: Data) async -> IPCResponse {
        guard let request = try? JSONDecoder().decode(IPCRequest.self, from: data) else {
            return .failure("Invalid JSON request")
        }

        guard let appState else {
            return .failure("App state unavailable")
        }

        let params = request.params ?? [:]

        switch request.action {
        case "listSessions":
            return listSessions(appState)

        case "addSession":
            return addSession(appState, params: params)

        case "removeSession":
            return removeSession(appState, params: params)

        case "selectSession":
            return selectSession(appState, params: params)

        case "renameSession":
            return renameSession(appState, params: params)

        case "listFolders":
            return listFolders(appState)

        case "addFolder":
            return addFolder(appState, params: params)

        case "removeFolder":
            return removeFolder(appState, params: params)

        case "createWorktree":
            return await createWorktree(appState, params: params)

        case "listSandboxes":
            let sandboxes = appState.sandboxes.map { sandbox in
                IPCValue.object([
                    "name": .string(sandbox.name),
                    "agent": .string(sandbox.agent),
                    "status": .string(sandbox.status),
                    "workspaces": .array(sandbox.workspaces.map { .string($0) }),
                ])
            }
            return .success(.array(sandboxes))

        case "createSandbox":
            return await createSandboxAction(appState, params: params)

        case "stopSandbox":
            guard let name = params["name"]?.stringValue else {
                return .failure("Missing 'name' parameter")
            }
            appState.stopSandbox(name: name)
            return .success()

        case "removeSandbox":
            guard let name = params["name"]?.stringValue else {
                return .failure("Missing 'name' parameter")
            }
            appState.removeSandbox(name: name)
            return .success()

        default:
            return .failure("Unknown action: \(request.action)")
        }
    }

    // MARK: - Action Handlers

    private func listSessions(_ state: AppState) -> IPCResponse {
        let sessions = state.sessions.map { session in
            IPCValue.object([
                "id": .string(session.id.uuidString),
                "title": .string(state.displayState(for: session.id)?.title ?? session.title),
                "folderID": .string(session.folderID.uuidString),
                "workingDirectory": .string(session.workingDirectory),
                "worktreePath": session.worktreePath.map { .string($0) } ?? .null,
                "branchName": session.branchName.map { .string($0) } ?? .null,
                "sandboxName": session.sandboxName.map { .string($0) } ?? .null,
                "tmuxSessionName": .string(session.tmuxSessionName),
                "isSelected": .bool(state.selectedSessionID == session.id),
            ])
        }
        return .success(.array(sessions))
    }

    private func addSession(_ state: AppState, params: [String: IPCValue]) -> IPCResponse {
        guard let folderPath = params["folderPath"]?.stringValue else {
            return .failure("Missing 'folderPath' parameter")
        }

        guard let folder = state.folders.first(where: { $0.path == folderPath }) else {
            return .failure("Folder not found: \(folderPath)")
        }

        let title = params["title"]?.stringValue ?? folder.name
        let worktreePath = params["worktreePath"]?.stringValue
        let branchName = params["branchName"]?.stringValue
        let sandboxName = params["sandboxName"]?.stringValue
        let cwd = worktreePath ?? folderPath

        state.addSession(
            folderID: folder.id,
            title: title,
            cwd: cwd,
            worktreePath: worktreePath,
            branchName: branchName,
            sandboxName: sandboxName
        )

        guard let session = state.sessions.last else {
            return .failure("Failed to create session")
        }

        return .success(.object([
            "id": .string(session.id.uuidString),
            "tmuxSessionName": .string(session.tmuxSessionName),
        ]))
    }

    private func removeSession(_ state: AppState, params: [String: IPCValue]) -> IPCResponse {
        guard let idStr = params["sessionId"]?.stringValue,
              let sessionID = UUID(uuidString: idStr) else {
            return .failure("Missing or invalid 'sessionId' parameter")
        }

        guard state.sessions.contains(where: { $0.id == sessionID }) else {
            return .failure("Session not found: \(idStr)")
        }

        state.removeSession(id: sessionID)
        return .success()
    }

    private func selectSession(_ state: AppState, params: [String: IPCValue]) -> IPCResponse {
        guard let idStr = params["sessionId"]?.stringValue,
              let sessionID = UUID(uuidString: idStr) else {
            return .failure("Missing or invalid 'sessionId' parameter")
        }

        guard state.sessions.contains(where: { $0.id == sessionID }) else {
            return .failure("Session not found: \(idStr)")
        }

        state.selectedSessionID = sessionID
        return .success()
    }

    private func renameSession(_ state: AppState, params: [String: IPCValue]) -> IPCResponse {
        guard let idStr = params["sessionId"]?.stringValue,
              let sessionID = UUID(uuidString: idStr) else {
            return .failure("Missing or invalid 'sessionId' parameter")
        }

        guard let newTitle = params["newTitle"]?.stringValue else {
            return .failure("Missing 'newTitle' parameter")
        }

        guard state.sessions.contains(where: { $0.id == sessionID }) else {
            return .failure("Session not found: \(idStr)")
        }

        state.renameSession(id: sessionID, newTitle: newTitle)
        return .success()
    }

    private func listFolders(_ state: AppState) -> IPCResponse {
        let folders = state.folders.map { folder in
            IPCValue.object([
                "id": .string(folder.id.uuidString),
                "name": .string(folder.name),
                "path": .string(folder.path),
                "sessionCount": .int(folder.sessionIDs.count),
                "isGitRepo": .bool(folder.isGitRepo),
            ])
        }
        return .success(.array(folders))
    }

    private func addFolder(_ state: AppState, params: [String: IPCValue]) -> IPCResponse {
        guard let path = params["path"]?.stringValue else {
            return .failure("Missing 'path' parameter")
        }

        guard FileManager.default.fileExists(atPath: path) else {
            return .failure("Path does not exist: \(path)")
        }

        if state.folders.contains(where: { $0.path == path }) {
            return .failure("Folder already added: \(path)")
        }

        state.addFolder(path: path)

        guard let folder = state.folders.last else {
            return .failure("Failed to add folder")
        }

        return .success(.object([
            "id": .string(folder.id.uuidString),
            "name": .string(folder.name),
        ]))
    }

    private func removeFolder(_ state: AppState, params: [String: IPCValue]) -> IPCResponse {
        guard let idStr = params["folderId"]?.stringValue,
              let folderID = UUID(uuidString: idStr) else {
            return .failure("Missing or invalid 'folderId' parameter")
        }

        guard state.folders.contains(where: { $0.id == folderID }) else {
            return .failure("Folder not found: \(idStr)")
        }

        state.removeFolder(id: folderID)
        return .success()
    }

    private func createWorktree(_ state: AppState, params: [String: IPCValue]) async -> IPCResponse {
        guard let folderPath = params["folderPath"]?.stringValue else {
            return .failure("Missing 'folderPath' parameter")
        }

        guard let branch = params["branch"]?.stringValue else {
            return .failure("Missing 'branch' parameter")
        }

        guard let folder = state.folders.first(where: { $0.path == folderPath }) else {
            return .failure("Folder not found: \(folderPath)")
        }

        guard folder.isGitRepo else {
            return .failure("Folder is not a git repo: \(folderPath)")
        }

        let newBranch = params["newBranch"]?.stringValue
        let startPoint = params["startPoint"]?.stringValue
        let sandboxName = params["sandboxName"]?.stringValue
        let repoPath = folderPath
        let copySettings = state.copyClaudeSettingsToWorktrees

        do {
            let worktreePath: String = try await Task.detached {
                let path: String
                if let newBranch {
                    path = try GitService.addWorktreeNewBranch(
                        repoPath: repoPath,
                        newBranch: newBranch,
                        startPoint: startPoint
                    )
                } else {
                    path = try GitService.addWorktree(repoPath: repoPath, branch: branch)
                }
                if copySettings {
                    GitService.copyClaudeLocalSettings(from: repoPath, to: path)
                }
                return path
            }.value

            let branchName = newBranch ?? branch
            let title = branchName
            let cwd = worktreePath

            state.addSession(
                folderID: folder.id,
                title: title,
                cwd: cwd,
                worktreePath: worktreePath,
                branchName: branchName,
                ownsBranch: newBranch != nil,
                sandboxName: sandboxName
            )

            guard let session = state.sessions.last else {
                return .failure("Failed to create session after worktree")
            }

            return .success(.object([
                "sessionId": .string(session.id.uuidString),
                "worktreePath": .string(worktreePath),
                "tmuxSessionName": .string(session.tmuxSessionName),
            ]))
        } catch {
            return .failure("Failed to create worktree: \(error.localizedDescription)")
        }
    }

    private func createSandboxAction(_ state: AppState, params: [String: IPCValue]) async -> IPCResponse {
        guard let name = params["name"]?.stringValue else {
            return .failure("Missing 'name' parameter")
        }

        let agent = params["agent"]?.stringValue ?? "claude"
        guard let workspacesValue = params["workspaces"]?.arrayValue else {
            return .failure("Missing 'workspaces' parameter")
        }

        let workspaces = workspacesValue.compactMap(\.stringValue)
        guard !workspaces.isEmpty else {
            return .failure("'workspaces' must contain at least one path")
        }

        guard let sandboxAgent = SandboxAgent(rawValue: agent) else {
            return .failure("Invalid agent: \(agent). Valid: \(SandboxAgent.allCases.map(\.rawValue).joined(separator: ", "))")
        }

        state.createSandbox(name: name, agent: sandboxAgent, workspaces: workspaces)
        return .success()
    }
}
