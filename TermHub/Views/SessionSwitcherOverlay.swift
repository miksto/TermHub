import SwiftUI

struct SessionSwitcherOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let items = appState.sessionSwitcherItems
        let selectedIndex = appState.switcherSelectedIndex
        let inputRecencyRanks = appState.recentInputSessionRanks

        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Recent Sessions")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                HStack {
                                    Image(systemName: "terminal")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .lineLimit(1)
                                        if let folder = item.folderName {
                                            Text(folder)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if let sandboxName = item.sandboxName {
                                        Label(sandboxName, systemImage: "shippingbox")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .help("Sandbox: \(sandboxName)")
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            rowBackground(
                                                inputRecencyRank: inputRecencyRanks[item.id],
                                                isSelected: index == selectedIndex
                                            )
                                        )
                                }
                                .overlay {
                                    if index == selectedIndex {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.accentColor.opacity(0.8), lineWidth: 1)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .id(index)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 470)
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
            .frame(width: 350)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }

    private func rowBackground(inputRecencyRank: Int?, isSelected: Bool) -> Color {
        guard let rank = inputRecencyRank else {
            return isSelected ? Color.primary.opacity(0.1) : Color.clear
        }

        // Keep brightness consistent while progressively removing saturation.
        // Rank 0 is the most recently typed-in session; rank 9 is the oldest
        // session that receives an interaction-recency color.
        let progress = Double(rank) / 9.0
        let desaturation = progress * 0.9
        let recencyColor = Color.accentColor.mix(with: .gray, by: desaturation)
        return recencyColor.opacity(isSelected ? 0.38 : 0.28)
    }
}
