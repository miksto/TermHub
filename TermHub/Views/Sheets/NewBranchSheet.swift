import SwiftUI

struct NewBranchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let folder: ManagedFolder

    @State private var branchName = ""
    @State private var errorMessage: String?
    @State private var isCreating = false

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
                .disabled(!isValid || isCreating)
            }
        }
        .padding()
        .frame(minWidth: 350)
    }

    private func createWorktreeWithNewBranch() {
        let trimmed = branchName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        do {
            let worktreePath = try GitService.addWorktreeNewBranch(repoPath: folder.path, newBranch: trimmed)

            appState.addSession(
                folderID: folder.id,
                title: "\(folder.name) [\(trimmed)]",
                cwd: worktreePath,
                worktreePath: worktreePath,
                branchName: trimmed
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
