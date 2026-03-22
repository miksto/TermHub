import SwiftUI

struct SessionRowView: View {
    @Environment(AppState.self) private var appState
    let sessionID: UUID
    var onRemove: () -> Void

    @State private var isHovering = false
    @State private var isConfirming = false
    @State private var isRenaming = false
    @State private var editedTitle = ""
    @FocusState private var isTextFieldFocused: Bool

    private var session: TerminalSession? {
        appState.sessions.first(where: { $0.id == sessionID })
    }

    var body: some View {
        if let session {
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
                            appState.finishRenamingSession(id: sessionID)
                        }
                    } else {
                        Text(session.title)
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
                if let status = appState.gitStatus(forSession: session), status.isDirty {
                    DiffStatsText(status: status)
                }
                if appState.sessionsNeedingAttention.contains(sessionID) {
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
                Divider()
                Button("Close Session", role: .destructive) {
                    onRemove()
                }
            }
        }
    }


    private func startRenaming() {
        guard let session else { return }
        editedTitle = session.title
        isRenaming = true
        isTextFieldFocused = true
        appState.startRenamingSession(id: sessionID)
    }

    private func commitRename() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, let session, trimmed != session.title {
            appState.renameSession(id: sessionID, newTitle: trimmed)
        }
        isRenaming = false
        appState.finishRenamingSession(id: sessionID)
    }
}
