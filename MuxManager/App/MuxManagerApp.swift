import SwiftUI

@main
struct MuxManagerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    // Add a test folder if none exist, for initial verification
                    if appState.folders.isEmpty {
                        let home = FileManager.default.homeDirectoryForCurrentUser.path
                        appState.addFolder(path: home)
                    }
                }
        }
    }
}
