import Foundation

enum MCPTools {
    // MARK: - Tool Definitions

    static let allTools: [JSONValue] = [
        // Workspace Overview (IPC)
        toolDef(
            name: "get_workspace_overview",
            description: """
                Get a complete snapshot of the TermHub workspace: all managed folders, terminal sessions, \
                and Docker sandboxes in a single call. This is the best starting point to understand the \
                current state before taking any action. Returns folders (with id, name, path, git status), \
                sessions (with id, title, folder, branch, worktree, sandbox, selection state), and \
                sandboxes (with name, agent, status, workspaces). Use the returned IDs with other tools \
                like send_keys, select_session, or create_worktree.
                """,
            properties: [:],
            required: []
        ),

        // Session Management (IPC)
        toolDef(
            name: "list_sessions",
            description: """
                List terminal sessions managed by TermHub. Returns id, title, folderID, workingDirectory, \
                worktreePath, branchName, sandboxName, tmuxSessionName, and isSelected for each session. \
                Sessions with non-null worktreePath are git worktree sessions. Use get_workspace_overview \
                instead if you also need folder and sandbox information. Optionally filter by folderId to \
                get sessions for a specific folder only.
                """,
            properties: [
                "folderId": propString("Optional UUID of a folder to filter sessions by. Omit to list all sessions."),
            ],
            required: []
        ),
        toolDef(
            name: "add_session",
            description: """
                Create a new terminal session in a managed folder. The folder must already be added to \
                TermHub (use list_folders or get_workspace_overview to find valid folder paths). Returns \
                the new session's id and tmuxSessionName. For git worktree sessions, prefer create_worktree \
                which handles both worktree creation and session setup. Use send_keys with the returned \
                session id to run commands in the new session.
                """,
            properties: [
                "folderPath": propString("Absolute path of a managed folder already added to TermHub. Example: '/Users/me/projects/myapp'"),
                "title": propString("Display title for the session. Defaults to the folder name if omitted."),
                "worktreePath": propString("Absolute path to an existing git worktree directory, if this is a worktree session."),
                "branchName": propString("Git branch name associated with the worktree session."),
                "sandboxName": propString("Name of a Docker sandbox to run the session in. The sandbox must already exist (use create_sandbox first)."),
            ],
            required: ["folderPath"]
        ),
        toolDef(
            name: "remove_session",
            description: """
                Remove a terminal session from TermHub. This kills the associated tmux session and, if \
                the session is a worktree session, removes the git worktree directory. Use list_sessions \
                or get_workspace_overview to find the session UUID.
                """,
            properties: [
                "sessionId": propString("UUID of the session to remove. Get this from list_sessions or get_workspace_overview."),
            ],
            required: ["sessionId"]
        ),
        toolDef(
            name: "select_session",
            description: """
                Select and focus a terminal session in the TermHub UI. The session's terminal view becomes \
                visible in the main panel. Use list_sessions or get_workspace_overview to find the session UUID.
                """,
            properties: [
                "sessionId": propString("UUID of the session to select. Get this from list_sessions or get_workspace_overview."),
            ],
            required: ["sessionId"]
        ),
        toolDef(
            name: "rename_session",
            description: """
                Change the display title of a terminal session in TermHub. Use list_sessions or \
                get_workspace_overview to find the session UUID and its current title.
                """,
            properties: [
                "sessionId": propString("UUID of the session to rename. Get this from list_sessions or get_workspace_overview."),
                "newTitle": propString("New display title for the session."),
            ],
            required: ["sessionId", "newTitle"]
        ),

        // Folder Management (IPC)
        toolDef(
            name: "list_folders",
            description: """
                List managed folders in TermHub. Returns id, name, path, sessionCount, and isGitRepo for \
                each folder. Use get_workspace_overview instead if you also need session and sandbox \
                information. Folder IDs are needed for create_worktree and add_session.
                """,
            properties: [:],
            required: []
        ),
        toolDef(
            name: "add_folder",
            description: """
                Add a folder to TermHub for management. The folder must exist on disk. Once added, you \
                can create sessions and worktrees within it. Returns the new folder's id and name. Fails \
                if the folder is already managed by TermHub.
                """,
            properties: [
                "path": propString("Absolute filesystem path of the folder to add. Example: '/Users/me/projects/myapp'"),
            ],
            required: ["path"]
        ),
        toolDef(
            name: "remove_folder",
            description: """
                Remove a managed folder and all its sessions from TermHub. This kills all tmux sessions \
                and removes any worktrees associated with the folder's sessions. Use list_folders or \
                get_workspace_overview to find the folder UUID.
                """,
            properties: [
                "folderId": propString("UUID of the folder to remove. Get this from list_folders or get_workspace_overview."),
            ],
            required: ["folderId"]
        ),

        // Git Operations (direct)
        toolDef(
            name: "git_status",
            description: """
                Get git status for a repository or worktree path. Returns currentBranch, linesAdded, \
                linesDeleted, commits ahead/behind remote, and isDirty flag. Works with both main \
                repository paths and worktree paths. The path does not need to be managed by TermHub.
                """,
            properties: [
                "path": propString("Absolute path to a git repository or worktree directory. Example: '/Users/me/projects/myapp'"),
            ],
            required: ["path"]
        ),
        toolDef(
            name: "git_branches",
            description: """
                List git branches for a repository, sorted by most recent commit date (newest first). \
                Returns branch name, lastCommitDate (ISO 8601), and isCurrent flag for each branch. \
                Use this to find available branches before calling create_worktree.
                """,
            properties: [
                "repoPath": propString("Absolute path to the git repository root (not a worktree). Example: '/Users/me/projects/myapp'"),
            ],
            required: ["repoPath"]
        ),
        toolDef(
            name: "git_diff",
            description: """
                Get a summary of uncommitted changes in a git repository or worktree. Returns a list of \
                changed files with path, isBinary, linesAdded, and linesDeleted for each. Does not return \
                the actual diff content, only a per-file summary.
                """,
            properties: [
                "path": propString("Absolute path to a git repository or worktree directory. Example: '/Users/me/projects/myapp'"),
            ],
            required: ["path"]
        ),

        // Worktree Operations (hybrid)
        toolDef(
            name: "create_worktree",
            description: """
                Create a git worktree and automatically open it as a new terminal session in TermHub. \
                The folder must already be managed by TermHub and be a git repository (use list_folders \
                or get_workspace_overview to verify isGitRepo). Returns the new sessionId, worktreePath, \
                and tmuxSessionName. Use send_keys with the returned sessionId to run commands in the \
                new session. Use git_branches to find available branch names. Specify newBranch to create \
                a fresh branch, or branch to check out an existing one.
                """,
            properties: [
                "folderPath": propString("Absolute path of a managed folder that is a git repo. Get this from list_folders or get_workspace_overview."),
                "branch": propString("Branch name to check out. Use git_branches to see available branches. Also used as the worktree directory name."),
                "newBranch": propString("If set, create a new branch with this name instead of checking out an existing one. The branch parameter is still required as the base context."),
                "startPoint": propString("Git ref (commit SHA, tag, or branch name) to start the new branch from. Only used with newBranch. Defaults to HEAD if omitted."),
                "sandboxName": propString("Name of an existing Docker sandbox to run the session in."),
            ],
            required: ["folderPath", "branch"]
        ),

        // Tmux Operations (direct)
        toolDef(
            name: "send_keys",
            description: """
                Send text followed by Enter to a terminal session's tmux session. Use this to run shell \
                commands in a TermHub terminal. The session must exist and have an active tmux session. \
                Get session IDs from list_sessions, get_workspace_overview, create_worktree, or add_session. \
                Note: Enter is appended automatically — do not include a trailing newline in the text.
                """,
            properties: [
                "sessionId": propString("UUID of the session to send keys to. Get this from list_sessions or get_workspace_overview."),
                "text": propString("Text to type into the terminal. Enter is appended automatically. Example: 'git status'"),
            ],
            required: ["sessionId", "text"]
        ),

        // Sandbox Operations
        toolDef(
            name: "list_sandboxes",
            description: """
                List all Docker sandboxes with their name, agent type, status, and workspace paths. \
                Use get_workspace_overview instead if you also need folder and session information.
                """,
            properties: [:],
            required: []
        ),
        toolDef(
            name: "create_sandbox",
            description: """
                Create a new Docker sandbox environment. Sandboxes provide isolated containers for running \
                AI coding agents. At least one workspace path must be mounted. After creation, use \
                add_session with the sandbox name to open a terminal session inside it.
                """,
            properties: [
                "name": propString("Unique name for the sandbox. Example: 'my-feature-sandbox'"),
                "agent": propString("Agent type to run in the sandbox. Valid values: claude, copilot, codex, gemini, cagent, kiro, opencode, shell. Defaults to 'claude' if omitted."),
                "workspaces": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Absolute filesystem paths to mount as workspaces in the sandbox. At least one path is required. Example: ['/Users/me/projects/myapp']"),
                ]),
            ],
            required: ["name", "workspaces"]
        ),
        toolDef(
            name: "stop_sandbox",
            description: """
                Stop a running Docker sandbox container. The sandbox can be restarted later. \
                Use list_sandboxes or get_workspace_overview to find sandbox names and check status.
                """,
            properties: [
                "name": propString("Name of the sandbox to stop. Get this from list_sandboxes or get_workspace_overview."),
            ],
            required: ["name"]
        ),
        toolDef(
            name: "remove_sandbox",
            description: """
                Permanently remove a Docker sandbox and all its resources. This stops the container if \
                running and deletes it. This action cannot be undone. Use list_sandboxes or \
                get_workspace_overview to find sandbox names.
                """,
            properties: [
                "name": propString("Name of the sandbox to remove. Get this from list_sandboxes or get_workspace_overview."),
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
        case "get_workspace_overview",
             "list_sessions",
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
            return callViaIPC(action: snakeToCamelCase(name), arguments: arguments)

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

    private static func snakeToCamelCase(_ name: String) -> String {
        let parts = name.split(separator: "_")
        guard let first = parts.first else { return name }
        return String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

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
