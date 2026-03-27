import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(description: String, keys: String)] = [
        ("Assistant", "⌃Space"),
        ("Command Palette", "⌘P"),
        ("New Shell in Current Folder", "⌘T"),
        ("New Sandboxed Shell", "⌥⌘T"),
        ("Add Folder", "⌘O"),
        ("New Worktree", "⌘N"),
        ("Switch Branch / Worktree", "⌘B"),
        ("Close Session", "⌘W"),
        ("Switch Session (MRU)", "⌃Tab"),
        ("Switch Session (MRU, reverse)", "⌃⇧Tab"),
        ("Previous Session", "⌥⌘↑"),
        ("Next Session", "⌥⌘↓"),
        ("Previous Detail Tab", "⌥⌘←"),
        ("Next Detail Tab", "⌥⌘→"),
        ("Switch to Session 1–9", "⌘1–⌘9"),
        ("Jump to Notification", "⌘J"),
        ("Toggle Git Diff", "⌘D"),
        ("Keyboard Shortcuts", "⌘/"),
    ]

    private let optionModifiers: [(description: String, keys: String)] = [
        ("Show sandbox indicators", "Hold ⌥"),
        ("New shell as sandboxed", "⌥ + click shell button"),
    ]

    @ViewBuilder
    private func shortcutRow(_ shortcut: (description: String, keys: String)) -> some View {
        GridRow {
            Text(shortcut.description)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(shortcut.keys)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Keyboard Shortcuts")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 0) {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        ForEach(shortcuts, id: \.description) { shortcut in
                            shortcutRow(shortcut)
                        }
                    }
                    .padding(.horizontal, 32)

                    Text("Option Key Modifiers")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                        .padding(.bottom, 8)

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        ForEach(optionModifiers, id: \.description) { shortcut in
                            shortcutRow(shortcut)
                        }
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 16)
            }

            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 20)
        }
        .frame(width: 380, height: 540)
    }
}
