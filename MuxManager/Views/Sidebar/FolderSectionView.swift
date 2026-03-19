import SwiftUI

struct FolderSectionView: View {
    @Environment(AppState.self) private var appState
    let folder: ManagedFolder

    private var folderSessions: [TerminalSession] {
        appState.sessions.filter { $0.folderID == folder.id }
    }

    var body: some View {
        Section(folder.name) {
            ForEach(folderSessions) { session in
                SessionRowView(session: session)
                    .tag(session.id)
            }
        }
    }
}
