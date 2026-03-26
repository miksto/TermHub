import Foundation

enum MCPTools {
    // MARK: - Tool Definitions

    static let allTools: [JSONValue] = [
        // Session Management (IPC)
        toolDef(
            name: "list_sessions",
            description: "List all terminal sessions with their details (id, title, folder, branch, sandbox, selection state)",
            properties: [:],
            required: []
        ),
        toolDef(
            name: "add_session",
            description: "Create a new terminal session in a managed folder",
            properties: [
                "folderPath": propString("Path of the managed folder to add the session to"),
                "title": propString("Session title (defaults to folder name)"),
                "worktreePath": propString("Git worktree path if this is a worktree session"),
                "branchName": propString("Branch name for worktree sessions"),
                "sandboxName": propString("Docker sandbox name to run the session in"),
            ],
            required: ["folderPath"]
        ),
        toolDef(
            name: "remove_session",
            description: "Remove a terminal session (cleans up tmux session and worktree if applicable)",
            properties: [
                "sessionId": propString("UUID of the session to remove"),
            ],
            required: ["sessionId"]
        ),
        toolDef(
            name: "select_session",
            description: "Select and focus a terminal session in TermHub",
            properties: [
                "sessionId": propString("UUID of the session to select"),
            ],
            required: ["sessionId"]
        ),
        toolDef(
            name: "rename_session",
            description: "Rename a terminal session",
            properties: [
                "sessionId": propString("UUID of the session to rename"),
                "newTitle": propString("New title for the session"),
            ],
            required: ["sessionId", "newTitle"]
        ),

        // Folder Management (IPC)
        toolDef(
            name: "list_folders",
            description: "List all managed folders with their details (id, name, path, session count, git repo status)",
            properties: [:],
            required: []
        ),
        toolDef(
            name: "add_folder",
            description: "Add a folder to TermHub for management",
            properties: [
                "path": propString("Absolute path of the folder to add"),
            ],
            required: ["path"]
        ),
        toolDef(
            name: "remove_folder",
            description: "Remove a managed folder and all its sessions from TermHub",
            properties: [
                "folderId": propString("UUID of the folder to remove"),
            ],
            required: ["folderId"]
        ),

        // Git Operations (direct)
        toolDef(
            name: "git_status",
            description: "Get git status for a path: lines added/deleted, commits ahead/behind remote, current branch",
            properties: [
                "path": propString("Path to the git repository or worktree"),
            ],
            required: ["path"]
        ),
        toolDef(
            name: "git_branches",
            description: "List git branches sorted by most recent commit date",
            properties: [
                "repoPath": propString("Path to the git repository"),
            ],
            required: ["repoPath"]
        ),
        toolDef(
            name: "git_diff",
            description: "Get a summary of uncommitted file changes (files changed, lines added/deleted per file)",
            properties: [
                "path": propString("Path to the git repository or worktree"),
            ],
            required: ["path"]
        ),

        // Worktree Operations (hybrid)
        toolDef(
            name: "create_worktree",
            description: "Create a git worktree and open it as a new session in TermHub",
            properties: [
                "folderPath": propString("Path of the managed folder (git repo)"),
                "branch": propString("Branch name to check out in the worktree"),
                "newBranch": propString("If set, create a new branch with this name instead of checking out an existing one"),
                "startPoint": propString("Starting point for the new branch (commit, tag, or branch). Only used with newBranch"),
                "sandboxName": propString("Docker sandbox name to run the session in"),
            ],
            required: ["folderPath", "branch"]
        ),

        // Tmux Operations (direct)
        toolDef(
            name: "send_keys",
            description: "Send keystrokes to a terminal session's tmux session (text followed by Enter)",
            properties: [
                "sessionId": propString("UUID of the session to send keys to"),
                "text": propString("Text to send (Enter is appended automatically)"),
            ],
            required: ["sessionId", "text"]
        ),

        // Sandbox Operations
        toolDef(
            name: "list_sandboxes",
            description: "List all Docker sandboxes with their status",
            properties: [:],
            required: []
        ),
        toolDef(
            name: "create_sandbox",
            description: "Create a new Docker sandbox",
            properties: [
                "name": propString("Name for the sandbox"),
                "agent": propString("Agent type: claude, copilot, codex, gemini, cagent, kiro, opencode, shell (default: claude)"),
                "workspaces": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Workspace paths to mount in the sandbox"),
                ]),
            ],
            required: ["name", "workspaces"]
        ),
        toolDef(
            name: "stop_sandbox",
            description: "Stop a running Docker sandbox",
            properties: [
                "name": propString("Name of the sandbox to stop"),
            ],
            required: ["name"]
        ),
        toolDef(
            name: "remove_sandbox",
            description: "Remove a Docker sandbox and its resources",
            properties: [
                "name": propString("Name of the sandbox to remove"),
            ],
            required: ["name"]
        ),
    ]

    // MARK: - Tool Dispatch

    static func call(name: String, arguments: [String: JSONValue]) -> JSONValue {
        switch name {
        // Direct operations
        case "git_status":
            return gitStatus(arguments)
        case "git_branches":
            return gitBranches(arguments)
        case "git_diff":
            return gitDiff(arguments)
        case "send_keys":
            return sendKeys(arguments)

        // IPC operations (through TermHub app)
        case "list_sessions",
             "add_session",
             "remove_session",
             "select_session",
             "rename_session",
             "list_folders",
             "add_folder",
             "remove_folder",
             "create_worktree",
             "list_sandboxes",
             "create_sandbox",
             "stop_sandbox",
             "remove_sandbox":
            return callViaIPC(action: name, arguments: arguments)

        default:
            return errorResult("Unknown tool: \(name)")
        }
    }

    // MARK: - Direct Tool Implementations

    private static func gitStatus(_ args: [String: JSONValue]) -> JSONValue {
        guard let path = args["path"]?.stringValue else {
            return errorResult("Missing 'path' parameter")
        }

        let status = GitService.status(path: path)
        return .object([
            "currentBranch": status.currentBranch.map { .string($0) } ?? .null,
            "linesAdded": .int(status.linesAdded),
            "linesDeleted": .int(status.linesDeleted),
            "ahead": .int(status.ahead),
            "behind": .int(status.behind),
            "isDirty": .bool(status.isDirty),
        ])
    }

    private static func gitBranches(_ args: [String: JSONValue]) -> JSONValue {
        guard let repoPath = args["repoPath"]?.stringValue else {
            return errorResult("Missing 'repoPath' parameter")
        }

        do {
            let result = try GitService.listBranchesWithDatesAndCurrent(repoPath: repoPath)
            let formatter = ISO8601DateFormatter()
            let branches = result.branches.map { branch in
                JSONValue.object([
                    "name": .string(branch.branch),
                    "lastCommitDate": .string(formatter.string(from: branch.date)),
                    "isCurrent": .bool(branch.branch == result.currentBranch),
                ])
            }
            return .object([
                "branches": .array(branches),
                "currentBranch": result.currentBranch.map { .string($0) } ?? .null,
            ])
        } catch {
            return errorResult("Failed to list branches: \(error.localizedDescription)")
        }
    }

    private static func gitDiff(_ args: [String: JSONValue]) -> JSONValue {
        guard let path = args["path"]?.stringValue else {
            return errorResult("Missing 'path' parameter")
        }

        let raw = GitService.diff(path: path)
        let diff = GitService.parseDiff(raw)

        let files = diff.files.map { file in
            JSONValue.object([
                "path": .string(file.displayPath),
                "isBinary": .bool(file.isBinary),
                "linesAdded": .int(file.linesAdded),
                "linesDeleted": .int(file.linesDeleted),
            ])
        }

        return .object(["files": .array(files)])
    }

    private static func sendKeys(_ args: [String: JSONValue]) -> JSONValue {
        guard let sessionIdStr = args["sessionId"]?.stringValue else {
            return errorResult("Missing 'sessionId' parameter")
        }
        guard let text = args["text"]?.stringValue else {
            return errorResult("Missing 'text' parameter")
        }
        guard let sessionId = UUID(uuidString: sessionIdStr) else {
            return errorResult("Invalid sessionId UUID")
        }

        // Read state.json to find tmux session name
        guard let tmuxName = lookupTmuxSessionName(sessionId: sessionId) else {
            return errorResult("Session not found: \(sessionIdStr)")
        }

        do {
            try TmuxService.sendKeys(sessionName: tmuxName, text: text)
            return .object(["success": .bool(true)])
        } catch {
            return errorResult("Failed to send keys: \(error.localizedDescription)")
        }
    }

    private static func lookupTmuxSessionName(sessionId: UUID) -> String? {
        let stateURL: URL
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            stateURL = appSupport
                .appendingPathComponent("TermHub", isDirectory: true)
                .appendingPathComponent("state.json")
        } else {
            return nil
        }

        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return nil }

        return state.sessions.first(where: { $0.id == sessionId })?.tmuxSessionName
    }

    // MARK: - IPC Bridge

    private static func callViaIPC(action: String, arguments: [String: JSONValue]) -> JSONValue {
        // Convert JSONValue arguments to IPCValue
        let ipcParams = arguments.mapValues { jsonValueToIPCValue($0) }

        do {
            let response = try IPCClient.send(action: action, params: ipcParams.isEmpty ? nil : ipcParams)
            if response.ok {
                if let data = response.data {
                    return ipcValueToJSONValue(data)
                }
                return .object(["success": .bool(true)])
            } else {
                return errorResult(response.error ?? "Unknown IPC error")
            }
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    private static func jsonValueToIPCValue(_ value: JSONValue) -> IPCValue {
        switch value {
        case .string(let s): return .string(s)
        case .int(let i): return .int(i)
        case .double(let d): return .double(d)
        case .bool(let b): return .bool(b)
        case .null: return .null
        case .array(let arr): return .array(arr.map { jsonValueToIPCValue($0) })
        case .object(let obj): return .object(obj.mapValues { jsonValueToIPCValue($0) })
        }
    }

    private static func ipcValueToJSONValue(_ value: IPCValue) -> JSONValue {
        switch value {
        case .string(let s): return .string(s)
        case .int(let i): return .int(i)
        case .double(let d): return .double(d)
        case .bool(let b): return .bool(b)
        case .null: return .null
        case .array(let arr): return .array(arr.map { ipcValueToJSONValue($0) })
        case .object(let obj): return .object(obj.mapValues { ipcValueToJSONValue($0) })
        }
    }

    // MARK: - Test Helpers

    #if DEBUG
    static func testJsonValueToIPCValue(_ value: JSONValue) -> IPCValue {
        jsonValueToIPCValue(value)
    }

    static func testIpcValueToJSONValue(_ value: IPCValue) -> JSONValue {
        ipcValueToJSONValue(value)
    }
    #endif

    // MARK: - Helpers

    private static func toolDef(
        name: String,
        description: String,
        properties: [String: JSONValue],
        required: [String]
    ) -> JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map { .string($0) }),
            ]),
        ])
    }

    private static func propString(_ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "description": .string(description),
        ])
    }

    static func errorResult(_ message: String) -> JSONValue {
        .object([
            "isError": .bool(true),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(message),
                ]),
            ]),
        ])
    }

    static func textResult(_ value: JSONValue) -> JSONValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let text: String
        if let data = try? encoder.encode(value),
           let str = String(data: data, encoding: .utf8) {
            text = str
        } else {
            text = "null"
        }
        return .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text),
                ]),
            ]),
        ])
    }
}
