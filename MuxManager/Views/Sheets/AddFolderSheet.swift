import SwiftUI

struct AddFolderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Add Folder")
                .font(.headline)
            Text("Placeholder - will be implemented in Task 2")
                .foregroundStyle(.secondary)
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(minWidth: 300)
    }
}
