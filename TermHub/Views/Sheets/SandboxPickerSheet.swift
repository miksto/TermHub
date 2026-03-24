import SwiftUI

/// A picker sheet shown when option-clicking the Shell button with multiple sandboxes available.
struct ShellSandboxPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let folderID: UUID
    let folderName: String
    let cwd: String
    var worktreePath: String? = nil
    var branchName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Sandbox")
                .font(.headline)

            List {
                ForEach(appState.sandboxes, id: \.name) { sandbox in
                    Button {
                        let title: String
                        if let branchName {
                            title = "\(folderName) [\(branchName)]"
                        } else {
                            title = "\(folderName) – Shell"
                        }
                        appState.addSession(
                            folderID: folderID,
                            title: title,
                            cwd: cwd,
                            worktreePath: worktreePath,
                            branchName: branchName,
                            sandboxName: sandbox.name
                        )
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(sandbox.name)
                                Text("\(sandbox.agent) · \(sandbox.isRunning ? "Running" : sandbox.status.capitalized)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.bordered)
            .frame(minHeight: 100, maxHeight: 300)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
