import SwiftUI

struct BranchPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let folder: ManagedFolder

    @State private var branches: [String] = []
    @State private var searchText = ""
    @State private var selectedBranch: String?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var createError: String?
    @State private var isCreating = false
    @State private var showAttachConfirmation = false
    @State private var existingWorktreePath: String?

    private var filteredBranches: [String] {
        if searchText.isEmpty {
            return branches
        }
        return branches.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
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
                TextField("Search branches...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                List(filteredBranches, id: \.self, selection: $selectedBranch) { branch in
                    Text(branch)
                        .tag(branch)
                }
                .listStyle(.bordered)
                .frame(minHeight: 200)

                if let createError {
                    Text(createError)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Select") {
                    createWorktreeFromBranch()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedBranch == nil || isCreating)
            }
            .padding()
        }
        .frame(minWidth: 350, minHeight: 350)
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

    private func loadBranches() {
        isLoading = true
        loadError = nil
        do {
            branches = try GitService.listBranches(repoPath: folder.path)
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    private func createWorktreeFromBranch() {
        guard let branch = selectedBranch else { return }
        isCreating = true
        createError = nil

        do {
            let worktreePath = try GitService.addWorktree(repoPath: folder.path, branch: branch)

            appState.addSession(
                folderID: folder.id,
                title: "\(folder.name) [\(branch)]",
                cwd: worktreePath,
                worktreePath: worktreePath,
                branchName: branch
            )

            dismiss()
        } catch GitServiceError.worktreeAlreadyExists {
            do {
                if let path = try GitService.findExistingWorktree(repoPath: folder.path, branch: branch) {
                    existingWorktreePath = path
                    showAttachConfirmation = true
                } else {
                    createError = "A worktree for this branch already exists but could not be located."
                }
            } catch {
                createError = "A worktree for this branch already exists. \(error.localizedDescription)"
            }
            isCreating = false
        } catch {
            createError = error.localizedDescription
            isCreating = false
        }
    }

    private func attachExistingWorktree() {
        guard let branch = selectedBranch, let path = existingWorktreePath else { return }

        appState.addSession(
            folderID: folder.id,
            title: "\(folder.name) [\(branch)]",
            cwd: path,
            worktreePath: path,
            branchName: branch,
            isExternalWorktree: true
        )

        dismiss()
    }
}
