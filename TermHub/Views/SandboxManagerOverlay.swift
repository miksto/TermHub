import SwiftUI

struct SandboxManagerOverlay: View {
    @Environment(AppState.self) private var appState
    @State private var confirmingRemove: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            panel
                .frame(width: 760, height: 500)
                .background(.ultraThickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 30, y: 10)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Sandboxes")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Table
            tableContent

            Spacer(minLength: 0)

            // Footer
            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        let entries = buildEntries()

        if entries.isEmpty {
            VStack(spacing: 8) {
                Text("No sandboxes configured.")
                    .foregroundStyle(.secondary)
                Text("Configure a sandbox from a folder's context menu.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                // Column headers
                HStack(spacing: 0) {
                    columnHeader("Name", width: 170, leading: true)
                    columnHeader("Status", width: 90)
                    columnHeader("Agent", width: 80)
                    columnHeader("Folders", width: 120)
                    columnHeader("Sessions", width: nil)
                    columnHeader("Actions", width: 100)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.3))

                Divider()

                // Rows
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            tableRow(entry)
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }

    private func columnHeader(_ title: String, width: CGFloat?, leading: Bool = false) -> some View {
        Group {
            if let width {
                Text(title)
                    .frame(width: width, alignment: leading ? .leading : .leading)
            } else {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private func tableRow(_ entry: SandboxEntry) -> some View {
        let isInProgress = appState.sandboxOperationInProgress.contains(entry.name)
        let sandboxSessions = sessionsForSandbox(entry)

        return HStack(spacing: 0) {
            // Name
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(info: entry.info))
                    .frame(width: 10, height: 10)
                Text(entry.name)
                    .lineLimit(1)
            }
            .frame(width: 170, alignment: .leading)

            // Status
            Text(statusText(info: entry.info))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            // Agent
            Text(entry.info?.agent ?? "—")
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            // Folder
            Text(entry.linkedFolders.isEmpty ? "—" : entry.linkedFolders.map(\.name).joined(separator: ", "))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 120, alignment: .leading)

            // Sessions
            Group {
                if sandboxSessions.isEmpty {
                    Text("—")
                        .foregroundStyle(.secondary)
                } else {
                    Text(sandboxSessions.map(\.title).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(sandboxSessions.map(\.title).joined(separator: "\n"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Actions
            actionsCell(entry: entry, isInProgress: isInProgress)
                .frame(width: 100, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func sessionsForSandbox(_ entry: SandboxEntry) -> [TerminalSession] {
        let folderIDs = Set(entry.linkedFolders.map(\.id))
        return appState.sessions.filter { $0.isSandboxSession && folderIDs.contains($0.folderID) }
    }

    @ViewBuilder
    private func actionsCell(entry: SandboxEntry, isInProgress: Bool) -> some View {
        if isInProgress {
            ProgressView()
                .controlSize(.small)
        } else if let info = entry.info {
            HStack(spacing: 12) {
                if info.isRunning {
                    Button { appState.stopSandbox(name: entry.name) } label: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop")
                }

                if confirmingRemove == entry.name {
                    Button {
                        appState.removeSandbox(name: entry.name)
                        confirmingRemove = nil
                    } label: {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Confirm remove")

                    Button { confirmingRemove = nil } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel")
                } else {
                    Button { confirmingRemove = entry.name } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
            }
        } else {
            // Not yet created
            if let folder = entry.linkedFolders.first {
                Button { appState.createSandbox(name: entry.name, workspacePath: folder.path) } label: {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("Create sandbox")
            }
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

    private func dismiss() {
        appState.showSandboxManager = false
    }

    // MARK: - Data

    private func buildEntries() -> [SandboxEntry] {
        var entries: [SandboxEntry] = []
        var seenNames: Set<String> = []

        for sandbox in appState.sandboxes {
            let linkedFolders = appState.folders.filter { $0.sandboxName == sandbox.name }
            entries.append(SandboxEntry(name: sandbox.name, info: sandbox, linkedFolders: linkedFolders))
            seenNames.insert(sandbox.name)
        }

        for folder in appState.folders {
            if let name = folder.sandboxName, !seenNames.contains(name) {
                entries.append(SandboxEntry(name: name, info: nil, linkedFolders: [folder]))
                seenNames.insert(name)
            }
        }

        return entries
    }
}

private struct SandboxEntry: Identifiable {
    var id: String { name }
    let name: String
    let info: SandboxInfo?
    let linkedFolders: [ManagedFolder]
}
