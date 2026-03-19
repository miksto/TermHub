import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
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
