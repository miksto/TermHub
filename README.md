# TermHub

A native macOS app for managing terminal sessions across multiple project folders with automatic git worktree support.

![TermHub screenshot](screenshot.png)

## Features

- **Multi-folder terminal management** — Organize terminal sessions by project folder. Sessions persist automatically across restarts.
- **Git worktree integration** — Create worktrees from existing branches or new ones via a built-in branch picker with fuzzy search. Inline diff viewer and per-session change indicators in the sidebar.
- **Docker sandbox integration** — Run sessions in isolated Docker sandbox containers. Manage sandboxes from a dedicated overlay panel, then pick one when creating a shell or worktree via the split-button menu or `⌥⌘T`. Supports multiple agent types (Claude Code, GitHub Copilot, Codex, Gemini, and more).
- **Tmux-backed sessions** — Each session runs in tmux, so your work survives app restarts.
- **Command palette** — `⌘P` to quickly access actions, sessions, and branches.
- **Embedded terminal** — Full terminal emulator via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
- **Bell notifications** — Sessions that emit BEL show an attention badge in the sidebar.

### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘P | Command Palette |
| ⌘T | New Shell in Current Folder |
| ⌥⌘T | New Sandboxed Shell |
| ⌘N | New Worktree |
| ⌘O | Add Folder |
| ⌘B | Switch Branch / Worktree |
| ⌘W | Close Session |
| ⌘1–9 | Switch to Session 1–9 |
| ⌥⌘↑/↓ | Previous / Next Session |
| ⌘J | Jump to Notification |
| ⌘D | Toggle Git Diff |
| ⌥⌘←/→ | Previous / Next Detail Tab |
| ⌃Tab | Switch Session (MRU) |
| ⌃⇧Tab | Switch Session (MRU, reverse) |
| ⌘/ | Keyboard Shortcuts |

#### Option key modifiers

| Modifier | Action |
|----------|--------|
| Hold ⌥ | Show sandbox indicators on sidebar buttons |
| ⌥ + click shell button | Create sandboxed shell (picks sandbox automatically if only one exists) |
| ⌥ + create worktree | Create new worktree as sandboxed |

### Docker sandboxes

TermHub can run terminal sessions inside isolated Docker sandbox containers. This is useful for running AI coding agents in a sandboxed environment.

**Setting up a sandbox:**

1. Click the **shipping box icon** in the toolbar to open the sandbox manager
2. Create a sandbox by giving it a name, selecting an agent type, and mapping one or more project folders
3. The sandbox appears in the manager with controls to start, stop, and remove it

**Running sessions in a sandbox:**

- Click the **chevron** on the shell split-button in the sidebar to pick a sandbox for the new session
- Hold `⌥` when clicking the shell button to create a sandboxed session directly (if only one sandbox exists, it is selected automatically; otherwise a picker appears)
- Use `⌥⌘T` to create a new sandboxed shell in the current folder (shows a picker when multiple sandboxes exist)
- Sandboxed sessions show "Terminal (Sandboxed)" in the tab bar

**Environment variables:** In the sandbox manager, you can configure host environment variable names to forward into sandbox sessions (e.g. `MY_API_KEY`). Only the variable names are stored — values are read from the host environment each time a session starts.

**Supported agents:** Claude Code, GitHub Copilot, Codex, Gemini, Docker Agent, Kiro, OpenCode, and Shell.

### Claude Code integration

#### Bell notifications

To get notified in TermHub when [Claude Code](https://claude.com/claude-code) finishes, add this hook to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "printf '\\a' > /dev/tty" }]
      }
    ]
  }
}
```

The `> /dev/tty` is required so the BEL reaches the terminal rather than being captured by Claude Code's stdout.

#### URL scheme

TermHub registers the `termhub://` URL scheme for creating worktree sessions externally:

```
termhub://new-worktree?repo=/path/to/repo&branch=feature/xyz&plan=/path/to/plan.md&sandbox=my-sandbox
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `repo` | Yes | Absolute path to the git repository |
| `branch` | Yes | Branch name for the worktree |
| `plan` | No | Path to a plan file — if provided, runs `claude` to implement it in the new session |
| `sandbox` | No | Docker sandbox name — if provided, the new session runs inside the named sandbox |

#### MCP server

TermHub includes an MCP (Model Context Protocol) server that lets AI assistants like Claude Code manage terminal sessions, folders, worktrees, and sandboxes programmatically.

**Building and installing:**

```bash
make install-mcp   # builds and copies termhub-mcp to ~/.local/bin
```

**Configuring with Claude Code:** Add the server to your Claude Code MCP settings (`~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "termhub": {
      "command": "termhub-mcp"
    }
  }
}
```

Make sure `~/.local/bin` is in your `PATH`, or use the full path to the binary.

**Available tools:**

| Tool | Description |
|------|-------------|
| `get_workspace_overview` | Get a complete snapshot of folders, sessions, and sandboxes in one call |
| `list_sessions` | List all terminal sessions with details |
| `add_session` | Create a new session in a managed folder |
| `remove_session` | Remove a session (cleans up tmux/worktree) |
| `select_session` | Focus a session in TermHub |
| `rename_session` | Rename a session |
| `list_folders` | List all managed folders |
| `add_folder` | Add a folder to TermHub |
| `remove_folder` | Remove a managed folder and its sessions |
| `create_worktree` | Create a worktree and open it as a session |
| `send_keys` | Send keystrokes to a session's tmux |
| `list_sandboxes` | List Docker sandboxes |
| `create_sandbox` | Create a new Docker sandbox |
| `stop_sandbox` | Stop a running sandbox |
| `remove_sandbox` | Remove a sandbox |

#### Implement in worktree

When planning a feature with Claude Code on the main branch, you may want the implementation to happen in a separate git worktree. The `/implement-in-worktree` slash command bridges that gap:

```
/implement-in-worktree my-feature-branch
```

This uses the plan file from the current conversation, creates a new worktree and TermHub session for the given branch, and starts Claude with the plan — so you go from planning to isolated implementation in one step.

## Requirements

- macOS 14.0 (Sonoma) or later
- [Xcode](https://apps.apple.com/app/xcode/id497799835) (full app, not just Command Line Tools — required for the Metal compiler)
- [tmux](https://github.com/tmux/tmux) (recommended, for session persistence)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (optional, for sandbox support)

## Building

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project and [xcode-build-server](https://github.com/SolaWing/xcode-build-server) for LSP support.

If you get `cannot execute tool 'metal' due to missing Metal Toolchain`, make sure the full Xcode app is installed and selected:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

```bash
brew install xcodegen xcode-build-server tmux
make generate     # generate Xcode project from project.yml
make build        # build the app
make run          # build and launch the app
make test         # run the test suite
make install-mcp  # build and install the MCP server to ~/.local/bin
```

Or open in Xcode directly:

```bash
xcodegen generate
open TermHub.xcodeproj
```

## Claude Code

When working with [Claude Code](https://claude.com/claude-code), you can use the following slash commands:

- `/build` — Build the app and show only warnings, errors, and the result
- `/run` — Build the app and launch it
- `/test` — Run the test suite and show only test results
- `/regenerate-project` — Regenerate the Xcode project from `project.yml` and refresh the LSP config
