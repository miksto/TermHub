import SwiftUI

struct SandboxPopoverView: View {
    @Environment(AppState.self) private var appState
    @State private var confirmingRemove = false

    var body: some View {
        let folder = appState.folderForSelectedSession
        let sandboxName = folder?.sandboxName
        let info = sandboxName.flatMap { name in appState.sandboxes.first { $0.name == name } }
        let isInProgress = sandboxName.map { appState.sandboxOperationInProgress.contains($0) } ?? false

        VStack(alignment: .leading, spacing: 12) {
            if let sandboxName {
                configuredView(
                    sandboxName: sandboxName,
                    info: info,
                    isInProgress: isInProgress,
                    folderPath: folder?.path ?? ""
                )
            } else {
                unconfiguredView(folderID: folder?.id)
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear { confirmingRemove = false }
    }

    @ViewBuilder
    private func configuredView(
        sandboxName: String,
        info: SandboxInfo?,
        isInProgress: Bool,
        folderPath: String
    ) -> some View {
        // Header
        HStack {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
            Text(sandboxName)
                .font(.headline)
            Spacer()
        }

        // Status
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(info: info))
                .frame(width: 8, height: 8)
            Text(statusText(info: info))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Divider()

        // Actions
        if isInProgress {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Operation in progress…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if let info {
            if info.isRunning {
                Button {
                    appState.stopSandbox(name: sandboxName)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if confirmingRemove {
                HStack {
                    Text("Remove sandbox?")
                        .font(.subheadline)
                    Spacer()
                    Button("Cancel") {
                        confirmingRemove = false
                    }
                    .buttonStyle(.plain)
                    Button("Remove") {
                        appState.removeSandbox(name: sandboxName)
                        confirmingRemove = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
            } else {
                Button(role: .destructive) {
                    confirmingRemove = true
                } label: {
                    Label("Remove", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        } else {
            // Sandbox not created yet
            Button {
                appState.createSandbox(name: sandboxName, workspacePath: folderPath)
            } label: {
                Label("Create Sandbox", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func unconfiguredView(folderID: UUID?) -> some View {
        HStack {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
            Text("No Sandbox")
                .font(.headline)
        }

        Text("No Docker sandbox is configured for this folder.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        if let folderID {
            Divider()

            Button {
                appState.pendingSandboxConfigFolderID = folderID
            } label: {
                Label("Configure Sandbox…", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private func statusColor(info: SandboxInfo?) -> Color {
        guard let info else { return .orange }
        if info.isRunning { return .green }
        if info.isStopped { return .gray }
        return .orange
    }

    private func statusText(info: SandboxInfo?) -> String {
        guard let info else { return "Not Created" }
        if info.isRunning { return "Running" }
        if info.isStopped { return "Stopped" }
        return info.status.capitalized
    }
}
