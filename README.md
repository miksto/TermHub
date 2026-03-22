# TermHub

A native macOS app for managing terminal sessions across multiple project folders with automatic git worktree support.

![TermHub screenshot](screenshot.png)

## Features

- **Multi-folder terminal management** — Organize terminal sessions by project folder. Sessions persist automatically across restarts.
- **Git worktree integration** — Create worktrees from existing branches or new ones via a built-in branch picker with fuzzy search. Inline diff viewer and per-session change indicators in the sidebar.
- **Tmux-backed sessions** — Each session runs in tmux, so your work survives app restarts.
- **Command palette** — `⌘P` to quickly access actions, sessions, and branches.
- **Embedded terminal** — Full terminal emulator via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
- **Bell notifications** — Sessions that emit BEL show an attention badge in the sidebar.

### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘P | Command Palette |
| ⌘T | New Shell in Current Folder |
| ⌘N | New Worktree |
| ⌘O | Add Folder |
| ⌘B | Switch Branch / Worktree |
| ⌘W | Close Session |
| ⌘1–9 | Switch to Session 1–9 |
| ⌥⌘↑/↓ | Previous / Next Session |
| ⇧⌘D | Toggle Git Diff |
| ⌥⌘←/→ | Previous / Next Detail Tab |
| ⇧⌘K | Show Keyboard Shortcuts |

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
termhub://new-worktree?repo=/path/to/repo&branch=feature/xyz&plan=/path/to/plan.md
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `repo` | Yes | Absolute path to the git repository |
| `branch` | Yes | Branch name for the worktree |
| `plan` | No | Path to a plan file — if provided, runs `claude` to implement it in the new session |

## Requirements

- macOS 14.0 (Sonoma) or later
- [tmux](https://github.com/tmux/tmux) (recommended, for session persistence)

## Building

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project:

```bash
brew install xcodegen tmux
xcodegen generate
open TermHub.xcodeproj
```

Or build from the command line (after running `xcodegen generate`):

```bash
xcodebuild -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHub build
```

## Running Tests

```bash
xcodebuild -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHub test
```

## Claude Code

When working with [Claude Code](https://claude.com/claude-code), you can use the following slash commands:

- `/build` — Build the app and show only warnings, errors, and the result
- `/test` — Run the test suite and show only test results
- `/regenerate-project` — Regenerate the Xcode project from `project.yml` and refresh the LSP config
