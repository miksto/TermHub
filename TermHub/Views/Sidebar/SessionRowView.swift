import SwiftUI

struct SessionRowView: View {
    @Environment(AppState.self) private var appState
    let sessionID: UUID
    var onRemove: () -> Void

    @State private var isHovering = false
    @State private var isConfirming = false
    @FocusState private var isTextFieldFocused: Bool

    /// Static session data (branchName, worktreePath, etc.) — read from the
    /// @ObservationIgnored sessions array so it doesn't create observation dependencies.
    private var session: TerminalSession? {
        appState.sessions.first(where: { $0.id == sessionID })
    }

    private var isRenaming: Bool {
        appState.renamingSessionID == sessionID
    }

    var body: some View {
        @Bindable var state = appState
        // Observe only this session's display state — title changes on other sessions
        // won't trigger a re-render of this view.
        let displayState = appState.displayState(for: sessionID)
        if let session {
            HStack {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    if isRenaming {
                        TextField("Session name", text: $state.renamingEditText, onCommit: {
                            commitRename()
                        })
                        .textFieldStyle(.plain)
                        .focused($isTextFieldFocused)
                        .onExitCommand {
                            appState.finishRenamingSession(id: sessionID)
                        }
                    } else {
                        Text(displayState?.title ?? session.title)
                            .lineLimit(1)
                            .overlay {
                                DoubleClickView {
                                    startRenaming()
                                }
                            }
                    }
                }
                Spacer()
                if let sandboxName = session.sandboxName {
                    Image(systemName: "shippingbox")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Sandbox: \(sandboxName)")
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
                if let worktreePath = session.worktreePath {
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(worktreePath, forType: .string)
                    }
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
    }


    private func startRenaming() {
        appState.startRenamingSession(id: sessionID)
        isTextFieldFocused = true
    }

    private func commitRename() {
        let trimmed = appState.renamingEditText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, let session, trimmed != session.title {
            appState.renameSession(id: sessionID, newTitle: trimmed)
        }
        appState.finishRenamingSession(id: sessionID)
    }
}
