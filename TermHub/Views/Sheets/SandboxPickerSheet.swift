import SwiftUI

/// A picker sheet shown when option-clicking the Shell button with multiple sandboxes available.
struct ShellSandboxPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let folderID: UUID
    let folderName: String
    let cwd: String
    var worktreePath: String? = nil
    var branchName: String? = nil
    var initialSandboxName: String? = nil

    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Select Sandbox")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()

            sandboxListView

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
                .disabled(appState.sandboxes.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            isFocused = true
            if let initialSandboxName,
               let index = appState.sandboxes.firstIndex(where: { $0.name == initialSandboxName }) {
                selectedIndex = index
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < appState.sandboxes.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.return) {
            confirmSelection()
            return .handled
        }
    }

    private var sandboxListView: some View {
        let sandboxes = appState.sandboxes
        return Group {
            if sandboxes.isEmpty {
                Text("No sandboxes available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(sandboxes.enumerated()), id: \.element.name) { index, sandbox in
                                sandboxRow(sandbox: sandbox, isSelected: index == selectedIndex)
                                    .id(sandbox.name)
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
                        if newIndex < sandboxes.count {
                            withAnimation {
                                proxy.scrollTo(sandboxes[newIndex].name, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sandboxRow(sandbox: SandboxInfo, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(sandbox.name)
                .foregroundStyle(.primary)

            Spacer()

            Text("\(sandbox.agent) \u{00B7} \(sandbox.isRunning ? "Running" : sandbox.status.capitalized)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if sandbox.isRunning {
                Circle()
                    .fill(.green)
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

    private func confirmSelection() {
        let sandboxes = appState.sandboxes
        guard selectedIndex < sandboxes.count else { return }
        let sandbox = sandboxes[selectedIndex]

        let title: String
        if let branchName {
            title = "\(folderName) [\(branchName)]"
        } else {
            title = "\(folderName) \u{2013} Shell"
        }
        appState.addSession(
            folderID: folderID,
            title: title,
            cwd: cwd,
            worktreePath: worktreePath,
            branchName: branchName,
            sandboxName: sandbox.name
        )
        dismiss()
    }
}
