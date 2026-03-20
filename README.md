# TermHub

A native macOS app for managing terminal sessions across multiple project folders with automatic git worktree support.

## Features

- **Multi-folder terminal management** — Add project folders and organize terminal sessions under each one. Sessions are persisted and restored automatically.
- **Git worktree integration** — Create worktrees from existing branches or start new ones directly from the sidebar. Worktrees are cleaned up when sessions are removed.
- **Tmux-backed sessions** — Each terminal session is backed by a tmux session, so your work survives app restarts. Falls back to plain shell processes if tmux isn't installed.
- **Embedded terminal** — Full terminal emulator built into the app via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). No need to switch to a separate terminal app.
- **Keyboard navigation** — `Cmd+T` new shell, `Cmd+N` add folder, `Cmd+W` close session, `Cmd+Option+↑/↓` switch sessions.
- **Bell attention notifications** — When a terminal session emits a BEL character (`\a`), a red dot appears on that session in the sidebar. The badge clears when you select the session. Useful for knowing which session needs attention without checking each one.

### Claude Code integration

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
xcodebuild -project TermHub.xcodeproj -scheme TermHub -destination 'platform=macOS' build
```

## Running Tests

```bash
xcodebuild -project TermHub.xcodeproj -scheme TermHub -destination 'platform=macOS' test
```
