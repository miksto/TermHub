import AppKit
import SwiftUI

struct ShellSplitButton: View {
    @Environment(AppState.self) private var appState

    let folderID: UUID
    let folderName: String
    let cwd: String
    var worktreePath: String? = nil
    var branchName: String? = nil
    var optionKeyDown: Bool = false
    var pathExists: Bool = true

    var body: some View {
        if appState.sandboxes.isEmpty {
            Button { createSession(sandboxName: nil) } label: {
                Label("Shell", systemImage: "terminal")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            shellMenuButton
        }
    }

    private var menuLabel: some View {
        SandboxSwappableLabel(
            title: "Shell",
            systemImage: "terminal",
            showSandboxIcon: false
        )
    }

    private var shellMenuButton: some View {
        ZStack {
            // Hidden Menu used only to establish the width (includes chevron space)
            Menu { EmptyView() } label: { menuLabel }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .hidden()

            if optionKeyDown {
                Button {
                    if appState.sandboxes.count == 1 {
                        createSession(sandboxName: appState.sandboxes[0].name)
                    } else {
                        appState.pendingSandboxPickerContext = AppState.SandboxPickerContext(
                            folderID: folderID,
                            folderName: folderName,
                            cwd: cwd,
                            worktreePath: worktreePath,
                            branchName: branchName
                        )
                    }
                } label: {
                    SandboxSwappableLabel(
                        title: "Shell",
                        systemImage: "terminal",
                        showSandboxIcon: true
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Menu {
                    Button { createSession(sandboxName: nil) } label: {
                        Label("Shell", systemImage: "terminal")
                    }
                    Divider()
                    ForEach(appState.sandboxes, id: \.name) { sandbox in
                        Button { createSession(sandboxName: sandbox.name) } label: {
                            Label(sandbox.name, systemImage: "shippingbox")
                        }
                    }
                } label: {
                    menuLabel
                } primaryAction: {
                    createSession(sandboxName: nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .fixedSize()
    }

    private var sessionTitle: String {
        if let branchName {
            "\(folderName) [\(branchName)]"
        } else {
            "\(folderName) – Shell"
        }
    }

    private func createSession(sandboxName: String?) {
        if !pathExists {
            appState.errorMessage = "Cannot create session: folder path no longer exists at \(cwd)"
            return
        }
        appState.addSession(
            folderID: folderID,
            title: sessionTitle,
            cwd: cwd,
            worktreePath: worktreePath,
            branchName: branchName,
            sandboxName: sandboxName
        )
    }
}
