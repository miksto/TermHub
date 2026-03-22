import SwiftUI

struct TerminalSearchBar: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var caseSensitive = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                        findPrevious()
                    } else {
                        findNext()
                    }
                }
                .onChange(of: searchText) {
                    if searchText.isEmpty, let id = appState.selectedSessionID {
                        appState.terminalManager.clearSearch(sessionID: id)
                    }
                }

            Toggle(isOn: $caseSensitive) {
                Text("Aa")
                    .font(.system(.caption, design: .monospaced))
            }
            .toggleStyle(.button)
            .controlSize(.small)

            Button(action: findPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: findNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .onAppear {
            isSearchFieldFocused = true
        }
        .onDisappear {
            if let id = appState.selectedSessionID {
                appState.terminalManager.clearSearch(sessionID: id)
            }
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private func findNext() {
        guard !searchText.isEmpty, let id = appState.selectedSessionID else { return }
        appState.terminalManager.findNext(sessionID: id, term: searchText, caseSensitive: caseSensitive)
    }

    private func findPrevious() {
        guard !searchText.isEmpty, let id = appState.selectedSessionID else { return }
        appState.terminalManager.findPrevious(sessionID: id, term: searchText, caseSensitive: caseSensitive)
    }

    private func dismiss() {
        appState.showSearchBar = false
    }
}
