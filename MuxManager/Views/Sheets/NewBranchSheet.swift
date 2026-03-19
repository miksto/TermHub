import SwiftUI

struct NewBranchSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("New Branch")
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
