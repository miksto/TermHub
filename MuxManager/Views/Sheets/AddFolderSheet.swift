import SwiftUI

struct AddFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Folder")
                .font(.headline)
            Text("Select a folder to manage with MuxManager.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Choose Folder...") {
                    openFolderPanel()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 320)
        .onAppear {
            openFolderPanel()
        }
    }

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            appState.addFolder(path: url.path)
            dismiss()
        } else {
            dismiss()
        }
    }
}
