import SwiftUI

struct NewBranchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let folder: ManagedFolder

    @State private var branchName = ""
    @State private var baseBranch = ""
    @State private var availableBranches: [String] = []
    @State private var errorMessage: String?
    @State private var isCreating = false
    @State private var isLoading = true

    private var isValid: Bool {
        !branchName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("New Branch Worktree")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Branch name:")
                    .font(.subheadline)
                TextField("feature/my-branch", text: $branchName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if isValid && !isCreating {
                            createWorktreeWithNewBranch()
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Based on:")
                    .font(.subheadline)
                HStack {
                    Picker("", selection: $baseBranch) {
                        if isLoading {
                            Text("Loading…").tag("")
                        }
                        ForEach(availableBranches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .labelsHidden()
                    .disabled(isLoading)
                    Spacer()
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    createWorktreeWithNewBranch()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isCreating || isLoading)
            }
        }
        .padding()
        .frame(minWidth: 350)
        .task {
            loadBranches()
        }
    }

    private func loadBranches() {
        isLoading = true
        do {
            let branches = try GitService.listBranches(repoPath: folder.path)
            let current = GitService.currentBranch(repoPath: folder.path)
            availableBranches = branches
            baseBranch = current ?? branches.first ?? ""
        } catch {
            availableBranches = []
        }
        isLoading = false
    }

    private func createWorktreeWithNewBranch() {
        let trimmed = branchName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        do {
            let startPoint = baseBranch.isEmpty ? nil : baseBranch
            let worktreePath = try GitService.addWorktreeNewBranch(
                repoPath: folder.path,
                newBranch: trimmed,
                startPoint: startPoint
            )

            appState.addSession(
                folderID: folder.id,
                title: "\(folder.name) [\(trimmed)]",
                cwd: worktreePath,
                worktreePath: worktreePath,
                branchName: trimmed,
                ownsBranch: true
            )

            dismiss()
        } catch GitServiceError.worktreeAlreadyExists {
            errorMessage = "A branch or worktree with this name already exists."
            isCreating = false
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }
}
