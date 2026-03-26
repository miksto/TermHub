import SwiftUI

struct SandboxManagerOverlay: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSandboxName: String?
    @State private var isCreatingNew = false
    @State private var showRemoveConfirmation = false
    @State private var newSandboxName = ""
    @State private var newSandboxWorkspaces: [String] = []
    @State private var newSandboxAgent: SandboxAgent = .claude
    @State private var newEnvVarName = ""
    @State private var panelSize = CGSize(width: 720, height: 480)
    @State private var dragStartSize = CGSize.zero
    @State private var dragStartLocation = CGPoint.zero

    private let minSize = CGSize(width: 620, height: 400)
    private let maxSize = CGSize(width: 1200, height: 900)
    private let listWidth: CGFloat = 200

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
        .onAppear { autoSelect() }
    }

    // MARK: - Panel Layout

    private var panel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Sandboxes")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // List-Detail split
            HStack(spacing: 0) {
                listPane
                    .frame(width: listWidth)

                Divider()

                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - List Pane

    private var listPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(buildEntries()) { entry in
                        listRow(entry)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            Divider()

            // Add button
            Button {
                isCreatingNew = true
                selectedSandboxName = nil
                resetCreateFields()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func listRow(_ entry: SandboxEntry) -> some View {
        let isSelected = !isCreatingNew && selectedSandboxName == entry.name

        return HStack(spacing: 8) {
            Circle()
                .fill(statusColor(entry: entry))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(entry.info?.agent ?? "creating…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isCreatingNew = false
            selectedSandboxName = entry.name
            newEnvVarName = ""
        }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if isCreatingNew {
            createForm
        } else if let name = selectedSandboxName, let entry = buildEntries().first(where: { $0.name == name }) {
            sandboxDetail(entry)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("No Sandboxes")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Create a sandbox to get started.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button {
                isCreatingNew = true
                selectedSandboxName = nil
                resetCreateFields()
            } label: {
                Label("Create Sandbox", systemImage: "plus")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sandbox Detail

    private func sandboxDetail(_ entry: SandboxEntry) -> some View {
        let isInProgress = appState.sandboxOperationInProgress.contains(entry.name)

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Status & Controls
                statusSection(entry: entry, isInProgress: isInProgress)

                Divider()

                // Mounted Folders
                foldersSection(entry: entry)

                Divider()

                // Active Sessions
                sessionsSection(entry: entry)

                Divider()

                // Environment Variables
                envVarsSection(sandboxName: entry.name)
            }
            .padding(20)
        }
        .confirmationDialog(
            "Remove sandbox \"\(entry.name)\"?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                let name = entry.name
                appState.removeSandbox(name: name)
                // Select next available sandbox
                let entries = buildEntries().filter { $0.name != name }
                selectedSandboxName = entries.first?.name
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the sandbox and all its data. This action cannot be undone.")
        }
    }

    // MARK: - Status Section

    private func statusSection(entry: SandboxEntry, isInProgress: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name + status badge
            HStack(spacing: 10) {
                Text(entry.name)
                    .font(.title3.weight(.semibold))

                statusBadge(entry: entry)

                if isInProgress {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Agent
            if let agent = entry.info?.agent {
                LabeledContent("Agent") {
                    Text(agent)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            // Action buttons
            if !isInProgress {
                HStack(spacing: 12) {
                    if let info = entry.info {
                        if info.isRunning {
                            Button {
                                appState.stopSandbox(name: entry.name)
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                        }

                        Button(role: .destructive) {
                            showRemoveConfirmation = true
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    } else if let folder = entry.linkedFolders.first {
                        Button {
                            appState.createSandbox(name: entry.name, workspacePath: folder.path)
                        } label: {
                            Label("Create", systemImage: "play.fill")
                        }
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func statusBadge(entry: SandboxEntry) -> some View {
        let color = statusColor(entry: entry)
        let text = statusText(entry: entry)

        return Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Folders Section

    private func foldersSection(entry: SandboxEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Mounted Folders")

            let workspaces = entry.info?.workspaces ?? []
            if workspaces.isEmpty {
                Text("No folders mounted.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(workspaces, id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(shortenPath(path))
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    // MARK: - Sessions Section

    private func sessionsSection(entry: SandboxEntry) -> some View {
        let sandboxSessions = appState.sessions.filter { $0.sandboxName == entry.name }

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Active Sessions")

            if sandboxSessions.isEmpty {
                Text("No active sessions.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(sandboxSessions) { session in
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(session.title)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
    }

    // MARK: - Environment Variables Section

    private func envVarsSection(sandboxName: String) -> some View {
        let keys = appState.environmentKeysForSandbox(sandboxName)

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Environment Variables")

            Text("Host environment variables to forward into sandbox sessions. Only variable names are stored — values are read from the host at session start.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)

            if keys.isEmpty {
                Text("No environment variables configured.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(keys, id: \.self) { key in
                    HStack(spacing: 6) {
                        Text(key)
                            .font(.callout.monospaced())
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
                    .frame(maxWidth: 280)
                }
            }

            HStack(spacing: 8) {
                TextField("VAR_NAME", text: $newEnvVarName)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                    .frame(width: 200)
                    .onSubmit { addEnvVar(to: sandboxName, keys: keys) }

                Button("Add") { addEnvVar(to: sandboxName, keys: keys) }
                    .disabled(!DockerSandboxService.isValidEnvVarKey(newEnvVarName) || keys.contains(newEnvVarName))
                    .font(.callout)
            }
        }
    }

    // MARK: - Create Form

    private var createForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("New Sandbox")
                        .font(.title3.weight(.semibold))

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow(alignment: .firstTextBaseline) {
                            Text("Name")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            TextField("my-sandbox", text: $newSandboxName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                        }

                        GridRow(alignment: .firstTextBaseline) {
                            Text("Agent")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $newSandboxAgent) {
                                ForEach(SandboxAgent.allCases, id: \.self) { agent in
                                    Text(agent.displayName).tag(agent)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mapped Folders")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if !newSandboxWorkspaces.isEmpty {
                            ForEach(Array(newSandboxWorkspaces.enumerated()), id: \.offset) { index, path in
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Text(shortenPath(path))
                                        .font(.callout)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Button {
                                        newSandboxWorkspaces.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            Text("At least one folder is required.")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }

                        Button {
                            addFolder()
                        } label: {
                            Label("Add Folder", systemImage: "plus.circle")
                                .font(.callout)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    isCreatingNew = false
                    autoSelect()
                }
                Button("Create") { submitCreateForm() }
                    .disabled(!canCreate)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Shared Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
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

    // MARK: - Helpers

    private var canCreate: Bool {
        DockerSandboxService.isValidSandboxName(newSandboxName) && !newSandboxWorkspaces.isEmpty
    }

    private func submitCreateForm() {
        let name = newSandboxName.trimmingCharacters(in: .whitespaces)
        guard DockerSandboxService.isValidSandboxName(name), !newSandboxWorkspaces.isEmpty else { return }
        appState.createSandbox(name: name, agent: newSandboxAgent, workspaces: newSandboxWorkspaces)
        isCreatingNew = false
        selectedSandboxName = name
        resetCreateFields()
    }

    private func resetCreateFields() {
        newSandboxName = ""
        newSandboxWorkspaces = []
        newSandboxAgent = .claude
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

    private func addEnvVar(to sandboxName: String, keys: [String]) {
        let name = newEnvVarName.trimmingCharacters(in: .whitespaces)
        guard DockerSandboxService.isValidEnvVarKey(name), !keys.contains(name) else { return }
        var updated = keys
        updated.append(name)
        appState.setSandboxEnvironmentKeys(updated, for: sandboxName)
        newEnvVarName = ""
    }

    private func autoSelect() {
        let entries = buildEntries()
        if let last = appState.lastUsedSandboxName, entries.contains(where: { $0.name == last }) {
            selectedSandboxName = last
        } else {
            selectedSandboxName = entries.first?.name
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
