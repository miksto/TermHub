# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TermHub is a native macOS app (Swift 6, SwiftUI) for managing terminal sessions across multiple project folders with tmux-backed persistence and git worktree integration. It embeds a terminal emulator via the [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) library.

## Build & Test Commands

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# Regenerate project (required after changing project.yml or adding/removing files)
xcodegen generate

# Build
xcodebuild -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHub build

# Run all tests (both schemes)
xcodebuild -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHub test
xcodebuild -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHubMCP test

# Run a single test class
xcodebuild -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHub test -only-testing:TermHubTests/AppStateTests
xcodebuild -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHubMCP test -only-testing:TermHubMCPTests/MCPServerTests

# Run a single test method
xcodebuild -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHub test -only-testing:TermHubTests/AppStateTests/testMethodName
```

Slash commands: `/build`, `/run` (build & launch), `/test`, `/regenerate-project`.

## Architecture

**App entry & state:** `TermHubApp` creates an `AppState` (the single `@Observable` object shared via SwiftUI environment). AppState owns all `ManagedFolder`s and `TerminalSession`s and is the central coordinator for adding/removing folders, sessions, worktrees, and tmux lifecycle.

**Models:**
- `ManagedFolder` — a project directory with an ordered list of session IDs and git repo detection
- `TerminalSession` — a terminal tab: references a folder, optional worktree/branch, and a generated tmux session name

**Services (stateless enums with static methods):**
- `TmuxService` — creates/kills/attaches tmux sessions on a dedicated socket (`termhub`)
- `GitService` — git worktree add/remove, branch listing, status, and diff parsing
- `PersistenceService` — JSON serialization of folders+sessions to `~/Library/Application Support/TermHub/state.json`
- `ShellEnvironment` — resolves user shell, PATH, and tmux binary location
- `GitFileWatcher` — FSEvents-based watcher on `.git` directories that triggers git status refreshes with debouncing

**ViewModels:**
- `TerminalSessionManager` — manages `SwiftTerm.LocalProcessTerminalView` instances per session, handles lazy tmux attach, and forwards bell/title-change callbacks to AppState
- `CommandPaletteState` — drives the command palette (`⌘P`): manages modes (commands, session/folder/branch picker, text input), fuzzy filtering, and action dispatch

**Views:** `ContentView` (NavigationSplitView) → sidebar (`SidebarView` with `FolderSectionView`/`SessionRowView`) + detail (`TerminalContainerView` wrapping `TermHubTerminalView` or `DiffTableView`). Sheets for branch picker, new branch, and keyboard shortcuts. `CommandPaletteOverlay` provides the `⌘P` palette.

**MCP Server (`TermHubMCP` target):** A separate command-line executable (`termhub-mcp`) that exposes TermHub functionality to AI agents via the Model Context Protocol over stdio. Communicates with the main app through a Unix domain socket IPC protocol.
- `MCPServer` — handles JSON-RPC message framing (Content-Length headers), request routing, and lifecycle
- `MCPProtocol` — JSON-RPC types (`JSONRPCRequest`, `JSONRPCResponse`, `JSONRPCId`, `JSONValue`)
- `MCPTools` — tool definitions and dispatch (git_status, git_branches, git_diff, send_keys, etc.)
- `IPCClient` — connects to the main TermHub app's Unix domain socket to forward tool calls

**URL scheme:** `termhub://new-worktree?repo=...&branch=...&plan=...&sandbox=...` — creates a worktree session externally. If `plan` is provided, runs `claude` to implement it in the new session. If `sandbox` is provided, the session runs inside the named Docker sandbox.

## Key Conventions

- **Swift 6 strict concurrency** — `SWIFT_STRICT_CONCURRENCY: complete` is enabled. AppState and TerminalSessionManager are `@MainActor`. Services use `nonisolated` static methods.
- **macOS 14.0+ deployment target** — no iOS/multiplatform considerations.
- **XcodeGen** — never edit `TermHub.xcodeproj` directly; modify `project.yml` and regenerate. Run `/regenerate-project` after adding/removing Swift files.
- **Tests use Swift Testing** (`import Testing`, `@Test`, `#expect`) not XCTest.

## Team Collaboration

This project uses a collaborative agent team for implementation. Use `/start-team` to bootstrap the team from the most recent plan file.
