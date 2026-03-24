import SwiftUI

struct SandboxPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let folder: ManagedFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Sandbox for \"\(folder.name)\"")
                .font(.headline)

            if appState.sandboxes.isEmpty {
                Text("No sandboxes available. Create one from the Sandbox Manager.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                List {
                    sandboxRow(name: nil, agent: nil, status: nil, isCurrent: folder.sandboxName == nil)
                    ForEach(appState.sandboxes, id: \.name) { sandbox in
                        sandboxRow(
                            name: sandbox.name,
                            agent: sandbox.agent,
                            status: sandbox.isRunning ? "Running" : sandbox.status.capitalized,
                            isCurrent: folder.sandboxName == sandbox.name
                        )
                    }
                }
                .listStyle(.bordered)
                .frame(minHeight: 150, maxHeight: 300)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func sandboxRow(name: String?, agent: String?, status: String?, isCurrent: Bool) -> some View {
        Button {
            appState.setSandboxName(name, forFolder: folder.id)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : (name == nil ? "xmark.circle" : "shippingbox"))
                    .foregroundStyle(isCurrent ? .blue : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? "None")
                        .fontWeight(isCurrent ? .semibold : .regular)
                    if let agent, !agent.isEmpty {
                        Text("\(agent) · \(status ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if name == nil {
                        Text("No sandbox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
