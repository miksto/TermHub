import SwiftUI

struct BranchPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Branch Picker")
                .font(.headline)
            Text("Placeholder - will be implemented in Task 3")
                .foregroundStyle(.secondary)
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(minWidth: 300)
    }
}
