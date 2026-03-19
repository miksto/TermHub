import SwiftUI

struct SessionRowView: View {
    @Environment(AppState.self) private var appState
    let session: TerminalSession
    var onRemove: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var editedTitle = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                if isRenaming {
                    TextField("Session name", text: $editedTitle, onCommit: {
                        commitRename()
                    })
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .onExitCommand {
                        isRenaming = false
                    }
                } else {
                    Text(session.title)
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            startRenaming()
                        }
                }
                if let branch = session.branchName {
                    Text(branch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isHovering && !isRenaming {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Rename...") {
                startRenaming()
            }
            Divider()
            Button("Close Session", role: .destructive) {
                onRemove()
            }
        }
    }

    private func startRenaming() {
        editedTitle = session.title
        isRenaming = true
        isTextFieldFocused = true
    }

    private func commitRename() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && trimmed != session.title {
            appState.renameSession(id: session.id, newTitle: trimmed)
        }
        isRenaming = false
    }
}
