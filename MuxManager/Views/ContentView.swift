import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            if !appState.tmuxAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("tmux not found — sessions won't persist across restarts")
                }
                .font(.callout)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.85))
            }

            NavigationSplitView {
                SidebarView()
            } detail: {
                if appState.selectedSessionID != nil {
                    TerminalContainerView(selectedSessionID: appState.selectedSessionID)
                } else {
                    Text("Select or create a session")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            ),
            presenting: appState.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {
                appState.errorMessage = nil
            }
        } message: { message in
            Text(message)
        }
    }
}
