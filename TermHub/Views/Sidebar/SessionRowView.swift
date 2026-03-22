import SwiftUI

struct SessionRowView: View {
    @Environment(AppState.self) private var appState
    let session: TerminalSession
    var onRemove: () -> Void

    @State private var isHovering = false
    @State private var isConfirming = false
    @State private var isRenaming = false
    @State private var editedTitle = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        // Observe only this session's display state for title updates.
        // Other sessions' title changes won't trigger a re-render.
        let displayTitle = appState.displayState(for: session.id)?.title ?? session.title
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
                        appState.finishRenamingSession(id: session.id)
                    }
                } else {
                    Text(displayTitle)
                        .lineLimit(1)
                        .overlay {
                            DoubleClickView {
                                startRenaming()
                            }
                        }
                }
                if let branch = session.branchName {
                    Text(branch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if appState.sessionsNeedingAttention.contains(session.id) {
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
            }
            if (isHovering || isConfirming) && !isRenaming {
                if isConfirming {
                    Button {
                        isConfirming = false
                        onRemove()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        isConfirming = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if !hovering {
                isConfirming = false
            }
        }
        .contextMenu {
            Button("Rename...") {
                startRenaming()
            }
            if let branchName = session.branchName {
                Button("Copy Branch Name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(branchName, forType: .string)
                }
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
        appState.startRenamingSession(id: session.id)
    }

    private func commitRename() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != session.title {
            appState.renameSession(id: session.id, newTitle: trimmed)
        }
        isRenaming = false
        appState.finishRenamingSession(id: session.id)
    }
}
