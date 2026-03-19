import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        List(selection: $state.selectedSessionID) {
            ForEach(appState.folders) { folder in
                FolderSectionView(folder: folder)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MuxManager")
    }
}
