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
                if let session = appState.selectedSession {
                    TerminalDetailView(session: session)
                } else {
                    Text("Select or create a session")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
