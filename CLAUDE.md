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

# Run all tests
xcodebuild -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHub test
```

Slash commands: `/build`, `/test`, `/regenerate-project`.

## Architecture

**App entry & state:** `TermHubApp` creates an `AppState` (the single `@Observable` object shared via SwiftUI environment). AppState owns all `ManagedFolder`s and `TerminalSession`s and is the central coordinator for adding/removing folders, sessions, worktrees, and tmux lifecycle.

**Models:**
- `ManagedFolder` — a project directory with an ordered list of session IDs and git repo detection
- `TerminalSession` — a terminal tab: references a folder, optional worktree/branch, and a generated tmux session name

**Services (stateless enums with static methods):**
- `TmuxService` — creates/kills/attaches tmux sessions on a dedicated socket (`termhub`)
- `GitService` — git worktree add/remove and branch listing
- `PersistenceService` — JSON serialization of folders+sessions to `~/Library/Application Support/TermHub/state.json`
- `ShellEnvironment` — resolves user shell, PATH, and tmux binary location

**ViewModels:**
- `TerminalSessionManager` — manages `SwiftTerm.LocalProcessTerminalView` instances per session, handles lazy tmux attach, and forwards bell/title-change callbacks to AppState

**Views:** `ContentView` (NavigationSplitView) → sidebar (`SidebarView` with `FolderSectionView`/`SessionRowView`) + detail (`TerminalContainerView` wrapping `TermHubTerminalView`). Sheets for branch picker, new branch, and keyboard shortcuts.

## Key Conventions

- **Swift 6 strict concurrency** — `SWIFT_STRICT_CONCURRENCY: complete` is enabled. AppState and TerminalSessionManager are `@MainActor`. Services use `nonisolated` static methods.
- **macOS 14.0+ deployment target** — no iOS/multiplatform considerations.
- **XcodeGen** — never edit `TermHub.xcodeproj` directly; modify `project.yml` and regenerate. Run `/regenerate-project` after adding/removing Swift files.
- **Tests use Swift Testing** (`import Testing`, `@Test`, `#expect`) not XCTest.

## Team Collaboration

This project uses a collaborative agent team for implementation. Use `/start-team` to bootstrap the team from the most recent plan file.
