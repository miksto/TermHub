import SwiftUI

struct BranchPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let folder: ManagedFolder

    @State private var branches: [BranchInfo] = []
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var createError: String?
    @State private var isCreating = false
    @State private var showAttachConfirmation = false
    @State private var existingWorktreePath: String?
    @FocusState private var isSearchFocused: Bool

    private var filteredBranches: [BranchInfo] {
        if searchText.isEmpty {
            return branches
        }
        return branches.compactMap { branch in
            if let score = FuzzyMatch.score(query: searchText, candidate: branch.name) {
                return (branch, score)
            }
            return nil
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.lastCommitDate > rhs.0.lastCommitDate
        }
        .map(\.0)
    }

    private var selectedBranch: BranchInfo? {
        let filtered = filteredBranches
        guard selectedIndex < filtered.count else { return nil }
        return filtered[selectedIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Worktree from Branch")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if isLoading {
                ProgressView("Loading branches...")
                    .padding()
            } else if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(loadError)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search branches...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                branchListView

                if let createError {
                    Text(createError)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Select") {
                    confirmSelection()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedBranch == nil || isCreating)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 400)
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: searchText) {
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            let count = filteredBranches.count
            if selectedIndex < count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.return) {
            confirmSelection()
            return .handled
        }
        .alert("Attach Existing Worktree?", isPresented: $showAttachConfirmation) {
            Button("Attach") {
                attachExistingWorktree()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let path = existingWorktreePath {
                Text("A worktree for this branch already exists at:\n\(path)\n\nWould you like to attach it as a session?")
            }
        }
        .task {
            loadBranches()
        }
    }

    private var branchListView: some View {
        let filtered = filteredBranches
        return Group {
            if filtered.isEmpty {
                Text(searchText.isEmpty ? "No branches" : "No results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, branch in
                                branchRow(branch: branch, isSelected: index == selectedIndex)
                                    .id(branch.id)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        TapGesture(count: 2)
                                            .onEnded {
                                                selectedIndex = index
                                                confirmSelection()
                                            }
                                            .simultaneously(with:
                                                TapGesture(count: 1)
                                                    .onEnded {
                                                        selectedIndex = index
                                                    }
                                            )
                                    )
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 200, maxHeight: 300)
                    .onChange(of: selectedIndex) { _, newIndex in
                        if newIndex < filtered.count {
                            withAnimation {
                                proxy.scrollTo(filtered[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    private func branchRow(branch: BranchInfo, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            // Current branch indicator
            if branch.isCurrentBranch {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            } else {
                Spacer().frame(width: 14)
            }

            // Branch name with dimmed prefix
            if let prefix = branch.prefix {
                Text(prefix)
                    .foregroundStyle(.secondary)
                +
                Text(branch.leafName)
                    .foregroundStyle(.primary)
            } else {
                Text(branch.name)
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Relative date
            Text(branch.relativeDate)
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Active session indicator
            if branch.hasActiveSession {
                Circle()
                    .fill(.blue)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
    }

    private func loadBranches() {
        isLoading = true
        loadError = nil
        do {
            let currentBranch = GitService.currentBranch(repoPath: folder.path)
            let branchesWithDates = try GitService.listBranchesWithDates(repoPath: folder.path)

            let activeBranches = Set(
                appState.sessions
                    .filter { $0.folderID == folder.id }
                    .compactMap(\.branchName)
            )

            branches = branchesWithDates.map { entry in
                BranchInfo(
                    name: entry.branch,
                    lastCommitDate: entry.date,
                    isCurrentBranch: entry.branch == currentBranch,
                    hasActiveSession: activeBranches.contains(entry.branch)
                )
            }
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    private func confirmSelection() {
        guard let branch = selectedBranch else { return }
        createWorktreeFromBranch(branch: branch)
    }

    private func createWorktreeFromBranch(branch: BranchInfo) {
        isCreating = true
        createError = nil

        do {
            if let path = try GitService.findExistingWorktree(repoPath: folder.path, branch: branch.name) {
                existingWorktreePath = path
                showAttachConfirmation = true
                isCreating = false
                return
            }

            let worktreePath = try GitService.addWorktree(repoPath: folder.path, branch: branch.name)

            appState.addSession(
                folderID: folder.id,
                title: "\(folder.name) [\(branch.name)]",
                cwd: worktreePath,
                worktreePath: worktreePath,
                branchName: branch.name
            )

            dismiss()
        } catch {
            createError = error.localizedDescription
            isCreating = false
        }
    }

    private func attachExistingWorktree() {
        guard let branch = selectedBranch, let path = existingWorktreePath else { return }

        appState.addSession(
            folderID: folder.id,
            title: "\(folder.name) [\(branch.name)]",
            cwd: path,
            worktreePath: path,
            branchName: branch.name,
            isExternalWorktree: true
        )

        dismiss()
    }
}
