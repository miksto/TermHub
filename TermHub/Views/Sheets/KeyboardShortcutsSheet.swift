import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(description: String, keys: String)] = [
        ("Command Palette", "⌘P"),
        ("New Shell in Current Folder", "⌘T"),
        ("Add Folder", "⌘N"),
        ("Close Session", "⌘W"),
        ("Previous Session", "⌥⌘↑"),
        ("Next Session", "⌥⌘↓"),
        ("Switch to Session 1–9", "⌘1–⌘9"),
        ("Find in Terminal", "⌘F"),
        ("Find Next", "Enter"),
        ("Find Previous", "⇧Enter"),
        ("Close Search", "Esc"),
        ("Keyboard Shortcuts", "⇧⌘K"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Keyboard Shortcuts")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                ForEach(shortcuts, id: \.description) { shortcut in
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
            }
            .padding(.horizontal, 32)

            Spacer()

            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 20)
        }
        .frame(width: 380, height: 440)
    }
}
