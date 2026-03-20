import SwiftUI

struct TerminalDetailView: View {
    @Environment(AppState.self) private var appState
    let session: TerminalSession

    var body: some View {
        TerminalNSViewWrapper(session: session)
            .id(session.id)
            .navigationTitle(session.title)
    }
}
