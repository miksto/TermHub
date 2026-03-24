import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @Bindable var paletteState: CommandPaletteState
    let dismiss: @MainActor () -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let currentItems = paletteState.items(appState: appState, dismiss: dismiss)

        VStack(spacing: 0) {
            // Search field
            searchField

            Divider()

            // Content area
            switch paletteState.currentMode {
            case .textInput(let prompt, let action):
                textInputView(prompt: prompt, action: action)
            case .gitActionStatus:
                gitActionStatusView
            default:
                itemListView(items: currentItems)
            }

            // Breadcrumbs
            if paletteState.breadcrumbs.count > 0 {
                Divider()
                breadcrumbBar
            }
        }
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .frame(width: 500)
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: paletteState.query) {
            paletteState.selectedIndex = 0
        }
        .onChange(of: currentItems.count) {
            paletteState.clampSelection(itemCount: currentItems.count)
        }
        .onKeyPress(.upArrow) {
            paletteState.moveSelectionUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            paletteState.moveSelectionDown(itemCount: currentItems.count)
            return .handled
        }
        .onKeyPress(.escape) {
            if !paletteState.popMode() {
                dismiss()
            }
            return .handled
        }
        .onKeyPress(.return) {
            handleReturn(items: currentItems)
            return .handled
        }
        .onKeyPress(.tab) {
            // Tab acts like down arrow
            paletteState.moveSelectionDown(itemCount: currentItems.count)
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search commands...", text: $paletteState.query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func itemListView(items: [PaletteItem]) -> some View {
        if paletteState.isLoadingBranches {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading branches...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if let error = paletteState.branchLoadError {
            Text(error)
                .foregroundStyle(.red)
                .padding()
        } else if items.isEmpty {
            Text(paletteState.query.isEmpty ? "No items" : "No results")
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            CommandPaletteRowView(item: item, isSelected: index == paletteState.selectedIndex)
                                .id(item.id)
                                .onTapGesture {
                                    paletteState.selectedIndex = index
                                    item.action()
                                }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
                .onChange(of: paletteState.selectedIndex) { _, newIndex in
                    if newIndex < items.count {
                        withAnimation {
                            proxy.scrollTo(items[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var gitActionStatusView: some View {
        VStack(spacing: 8) {
            if paletteState.isRunningGitAction {
                ProgressView()
                    .controlSize(.small)
                Text("Running \(paletteState.gitActionTitle)...")
                    .foregroundStyle(.secondary)
                Text(paletteState.gitActionCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else if let error = paletteState.gitActionError {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title2)
                Text("\(paletteState.gitActionTitle) failed")
                    .fontWeight(.medium)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func textInputView(prompt: String, action: TextInputAction) -> some View {
        VStack(spacing: 8) {
            Text(prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Type a name and press Enter")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(paletteState.breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(crumb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Esc to go back")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func handleReturn(items: [PaletteItem]) {
        switch paletteState.currentMode {
        case .textInput(_, let action):
            let text = paletteState.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            executeTextInputAction(action, text: text)
        default:
            guard paletteState.selectedIndex < items.count else { return }
            items[paletteState.selectedIndex].action()
        }
    }

    private func executeTextInputAction(_ action: TextInputAction, text: String) {
        switch action {
        case .renameSession(let sessionID):
            appState.renameSession(id: sessionID, newTitle: text)
            dismiss()
        case .newBranch(let folder):
            do {
                let worktreePath = try GitService.addWorktreeNewBranch(repoPath: folder.path, newBranch: text)
                appState.addSession(
                    folderID: folder.id,
                    title: "\(folder.name) / \(text)",
                    cwd: worktreePath,
                    worktreePath: worktreePath,
                    branchName: text,
                    ownsBranch: true
                )
            } catch {
                appState.errorMessage = error.localizedDescription
            }
            dismiss()
        case .configureSandbox(let folderID):
            if !text.isEmpty && !DockerSandboxService.isValidSandboxName(text) {
                appState.errorMessage = "Invalid sandbox name. Use only letters, numbers, dots, hyphens, and underscores."
            } else {
                appState.setSandboxName(text.isEmpty ? nil : text, forFolder: folderID)
            }
            dismiss()
        }
    }
}
