import SwiftUI

struct SandboxManagerOverlay: View {
    @Environment(AppState.self) private var appState
    @State private var confirmingRemove: String?
    @State private var showCreateForm = false
    @State private var newSandboxName = ""
    @State private var newSandboxWorkspaces: [String] = []

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.arrow.push()
                    } else {
                        NSCursor.pop()
                    }
                }

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

            // Create section
            Divider()
            if showCreateForm {
                createForm
                Divider()
            }

            // Footer
            HStack {
                if !showCreateForm {
                    Button {
                        showCreateForm = true
                    } label: {
                        Label("Create Sandbox", systemImage: "plus")
                    }
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Sandbox")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("my-sandbox", text: $newSandboxName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Mapped Folders")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !newSandboxWorkspaces.isEmpty {
                    ForEach(Array(newSandboxWorkspaces.enumerated()), id: \.offset) { index, path in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(shortenPath(path))
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                newSandboxWorkspaces.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Button {
                    addFolder()
                } label: {
                    Label("Add Folder", systemImage: "plus.circle")
                        .font(.callout)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Spacer()
                Button("Cancel") { resetCreateForm() }
                Button("Create") { submitCreateForm() }
                    .disabled(!canCreate)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var canCreate: Bool {
        DockerSandboxService.isValidSandboxName(newSandboxName) && !newSandboxWorkspaces.isEmpty
    }

    private func submitCreateForm() {
        let name = newSandboxName.trimmingCharacters(in: .whitespaces)
        guard DockerSandboxService.isValidSandboxName(name), !newSandboxWorkspaces.isEmpty else { return }
        appState.createSandbox(name: name, workspaces: newSandboxWorkspaces)
        resetCreateForm()
    }

    private func resetCreateForm() {
        newSandboxName = ""
        newSandboxWorkspaces = []
        showCreateForm = false
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            for url in panel.urls {
                let path = url.path(percentEncoded: false)
                if !newSandboxWorkspaces.contains(path) {
                    newSandboxWorkspaces.append(path)
                }
            }
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
            VStack(alignment: .leading, spacing: 2) {
                if sandboxSessions.isEmpty {
                    Text("—")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sandboxSessions) { session in
                        Text(session.title)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
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

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
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
