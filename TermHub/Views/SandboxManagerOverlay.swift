import SwiftUI

struct SandboxManagerOverlay: View {
    @Environment(AppState.self) private var appState
    @State private var confirmingRemove: String?
    @State private var showCreateForm = false
    @State private var newSandboxName = ""
    @State private var newSandboxWorkspaces: [String] = []
    @State private var newSandboxAgent: SandboxAgent = .claude
    @State private var panelSize = CGSize(width: 760, height: 500)
    @State private var dragStartSize = CGSize.zero
    @State private var dragStartLocation = CGPoint.zero
    @State private var expandedEnvSandbox: String?
    @State private var newEnvVarName = ""

    private let minSize = CGSize(width: 760, height: 500)
    private let maxSize = CGSize(width: 1200, height: 900)

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
                .frame(width: panelSize.width, height: panelSize.height)
                .background(.ultraThickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 30, y: 10)
                .overlay(alignment: .bottomTrailing) {
                    resizeHandle
                }
        }
        .coordinateSpace(name: "overlay")
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
            .frame(width: 16, height: 16)
            .padding(6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .named("overlay"))
                    .onChanged { value in
                        if dragStartSize == .zero {
                            dragStartSize = panelSize
                            dragStartLocation = value.startLocation
                        }
                        let deltaX = value.location.x - dragStartLocation.x
                        let deltaY = value.location.y - dragStartLocation.y
                        // Multiply by 2 because the panel is centered, so growth splits equally to both sides
                        let newWidth = max(minSize.width, min(maxSize.width, dragStartSize.width + deltaX * 2))
                        let newHeight = max(minSize.height, min(maxSize.height, dragStartSize.height + deltaY * 2))
                        panelSize = CGSize(width: newWidth, height: newHeight)
                    }
                    .onEnded { _ in
                        dragStartSize = .zero
                    }
            )
            .onHover { isHovered in
                if isHovered {
                    NSCursor(image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)!, hotSpot: NSPoint(x: 8, y: 8)).push()
                } else {
                    NSCursor.pop()
                }
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Agent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $newSandboxAgent) {
                    ForEach(SandboxAgent.allCases, id: \.self) { agent in
                        Text(agent.displayName).tag(agent)
                    }
                }
                .labelsHidden()
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
        appState.createSandbox(name: name, agent: newSandboxAgent, workspaces: newSandboxWorkspaces)
        resetCreateForm()
    }

    private func resetCreateForm() {
        newSandboxName = ""
        newSandboxWorkspaces = []
        newSandboxAgent = .claude
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
                HStack(spacing: 12) {
                    columnHeader("Name")
                        .frame(width: 130, alignment: .leading)
                    columnHeader("Status")
                        .frame(width: 60, alignment: .leading)
                    columnHeader("Agent")
                        .frame(width: 50, alignment: .leading)
                    columnHeader("Folders")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    columnHeader("Sessions")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    columnHeader("Actions")
                        .frame(width: 50, alignment: .trailing)
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

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func tableRow(_ entry: SandboxEntry) -> some View {
        let isInProgress = appState.sandboxOperationInProgress.contains(entry.name)
        let sandboxSessions = sessionsForSandbox(entry)
        let isExpanded = expandedEnvSandbox == entry.name

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Name
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor(entry: entry))
                        .frame(width: 10, height: 10)
                    Text(entry.name)
                        .lineLimit(1)
                }
                .frame(width: 130, alignment: .leading)

                // Status
                Text(statusText(entry: entry))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)

                // Agent
                Text(entry.info?.agent ?? "—")
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)

                // Folders (workspaces from Docker)
                VStack(alignment: .leading, spacing: 2) {
                    let workspaces = entry.info?.workspaces ?? []
                    if workspaces.isEmpty {
                        Text("—")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workspaces, id: \.self) { path in
                            Text(path)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
                    .frame(width: 50, alignment: .trailing)
            }
            .font(.callout)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedEnvSandbox = nil
                    } else {
                        expandedEnvSandbox = entry.name
                        newEnvVarName = ""
                    }
                }
            }

            if isExpanded {
                envVarsSection(sandboxName: entry.name)
            }
        }
    }

    private func envVarsSection(sandboxName: String) -> some View {
        let keys = appState.environmentKeysForSandbox(sandboxName)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Host Environment Variables")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if keys.isEmpty {
                Text("No environment variables configured.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(keys, id: \.self) { key in
                    HStack(spacing: 6) {
                        Text(key)
                            .font(.caption.monospaced())
                        Spacer()
                        Button {
                            var updated = keys
                            updated.removeAll { $0 == key }
                            appState.setSandboxEnvironmentKeys(updated, for: sandboxName)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 220)
                }
            }

            HStack(spacing: 8) {
                TextField("VAR_NAME", text: $newEnvVarName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 180)
                    .onSubmit { addEnvVar(to: sandboxName, keys: keys) }

                Button("Add") { addEnvVar(to: sandboxName, keys: keys) }
                    .disabled(!DockerSandboxService.isValidEnvVarKey(newEnvVarName) || keys.contains(newEnvVarName))
                    .font(.caption)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .padding(.leading, 30)
    }

    private func addEnvVar(to sandboxName: String, keys: [String]) {
        let name = newEnvVarName.trimmingCharacters(in: .whitespaces)
        guard DockerSandboxService.isValidEnvVarKey(name), !keys.contains(name) else { return }
        var updated = keys
        updated.append(name)
        appState.setSandboxEnvironmentKeys(updated, for: sandboxName)
        newEnvVarName = ""
    }

    private func sessionsForSandbox(_ entry: SandboxEntry) -> [TerminalSession] {
        return appState.sessions.filter { $0.sandboxName == entry.name }
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

    private func statusColor(entry: SandboxEntry) -> Color {
        if appState.sandboxOperationInProgress.contains(entry.name) { return .blue }
        guard let info = entry.info else { return .orange }
        if info.isRunning { return .green }
        if info.isStopped { return .gray }
        return .orange
    }

    private func statusText(entry: SandboxEntry) -> String {
        if appState.sandboxOperationInProgress.contains(entry.name), entry.info == nil { return "Creating…" }
        guard let info = entry.info else { return "Not Created" }
        if info.isRunning { return "Running" }
        if info.isStopped { return "Stopped" }
        return info.status.capitalized
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        let normalizedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        if path.hasPrefix(normalizedHome) {
            return "~" + path.dropFirst(normalizedHome.count)
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

        // Build a map of sandbox name → folders from active sessions
        var sandboxFolderMap: [String: Set<UUID>] = [:]
        for session in appState.sessions {
            if let name = session.sandboxName {
                sandboxFolderMap[name, default: []].insert(session.folderID)
            }
        }

        func linkedFolders(for name: String) -> [ManagedFolder] {
            guard let folderIDs = sandboxFolderMap[name] else { return [] }
            return appState.folders.filter { folderIDs.contains($0.id) }
        }

        for sandbox in appState.sandboxes {
            entries.append(SandboxEntry(name: sandbox.name, info: sandbox, linkedFolders: linkedFolders(for: sandbox.name)))
            seenNames.insert(sandbox.name)
        }

        // Show placeholder rows for sandboxes being created
        for name in appState.sandboxOperationInProgress where !seenNames.contains(name) {
            entries.append(SandboxEntry(name: name, info: nil, linkedFolders: []))
            seenNames.insert(name)
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
