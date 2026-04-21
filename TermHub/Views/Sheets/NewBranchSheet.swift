import SwiftUI

struct NewBranchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let folder: ManagedFolder
    var initialSandbox: String? = nil

    @State private var branchName = ""
    @State private var baseBranch = ""
    @State private var selectedSandbox: String?
    @State private var autoOpenAgent = true
    @State private var availableBranches: [String] = []
    @State private var errorMessage: String?
    @State private var isCreating = false
    @State private var isLoading = true

    private var isValid: Bool {
        !branchName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var selectedSandboxAgent: SandboxAgent? {
        guard let name = selectedSandbox,
              let sandbox = appState.sandboxes.first(where: { $0.name == name })
        else { return nil }
        return SandboxAgent(rawValue: sandbox.agent)
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

            if !appState.sandboxes.isEmpty {
                HStack {
                    Label("Sandbox:", systemImage: "shippingbox")
                        .font(.subheadline)
                    Picker("", selection: $selectedSandbox) {
                        Text("No Sandbox").tag(String?.none)
                        ForEach(appState.sandboxes, id: \.name) { sandbox in
                            Text(sandbox.name).tag(Optional(sandbox.name))
                        }
                    }
                    .labelsHidden()
                }
            }

            if let agent = selectedSandboxAgent, agent.autoLaunchCommand != nil {
                Toggle("Auto-open \(agent.displayName)", isOn: $autoOpenAgent)
                    .font(.subheadline)
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
            if let initialSandbox, appState.sandboxes.contains(where: { $0.name == initialSandbox }) {
                selectedSandbox = initialSandbox
            }
        }
    }

    private func loadBranches() {
        isLoading = true
        let folderPath = folder.path

        Task.detached {
            do {
                let branches = try GitService.listBranches(repoPath: folderPath)
                let preferred = GitService.defaultBranch(repoPath: folderPath)
                await MainActor.run {
                    availableBranches = branches
                    baseBranch = preferred ?? branches.first ?? ""
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    availableBranches = []
                    isLoading = false
                }
            }
        }
    }

    private func createWorktreeWithNewBranch() {
        let trimmed = branchName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        let folderPath = folder.path
        let folderID = folder.id
        let folderName = folder.name
        let startPoint = baseBranch.isEmpty ? nil : baseBranch

        Task.detached {
            do {
                let worktreePath = try GitService.addWorktreeNewBranch(
                    repoPath: folderPath,
                    newBranch: trimmed,
                    startPoint: startPoint
                )
                let shouldCopy = await MainActor.run { appState.copyClaudeSettingsToWorktrees }
                if shouldCopy {
                    GitService.copyClaudeLocalSettings(from: folderPath, to: worktreePath)
                }
                await MainActor.run {
                    appState.addSession(
                        folderID: folderID,
                        title: "\(folderName) [\(trimmed)]",
                        cwd: worktreePath,
                        worktreePath: worktreePath,
                        branchName: trimmed,
                        ownsBranch: true,
                        sandboxName: selectedSandbox
                    )
                    if autoOpenAgent,
                       let agent = selectedSandboxAgent,
                       let command = agent.autoLaunchCommand,
                       let sessionID = appState.selectedSessionID {
                        appState.terminalManager.pendingCommands[sessionID] = command
                    }
                    dismiss()
                }
            } catch GitServiceError.worktreeAlreadyExists {
                await MainActor.run {
                    errorMessage = "A branch or worktree with this name already exists."
                    isCreating = false
                }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run {
                    errorMessage = msg
                    isCreating = false
                }
            }
        }
    }
}
