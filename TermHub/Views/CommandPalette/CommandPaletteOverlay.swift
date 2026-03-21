import SwiftUI

struct CommandPaletteOverlay: View {
    @Environment(AppState.self) private var appState
    @State private var paletteState = CommandPaletteState()

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissPalette()
                }

            // Palette panel positioned near the top
            VStack {
                CommandPaletteView(
                    paletteState: paletteState,
                    dismiss: dismissPalette
                )
                .padding(.top, 80)

                Spacer()
            }
        }
    }

    private func dismissPalette() {
        appState.showCommandPalette = false
    }
}
