import SwiftUI

struct SessionSwitcherOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let items = appState.sessionSwitcherItems
        let selectedIndex = appState.switcherSelectedIndex

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
                                VStack(alignment: .leading, spacing: 3) {
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
                                        if appState.sessionsNeedingAttention.contains(item.id) {
                                            Circle()
                                                .fill(.red)
                                                .frame(width: 12, height: 12)
                                        }
                                        if let lastInputAt = appState.sessionLastInputAt[item.id] {
                                            Text(
                                                relativeInputTimeLabel(
                                                    lastInputAt,
                                                    relativeTo: appState.sessionSwitcherReferenceDate
                                                )
                                            )
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .monospacedDigit()
                                                .help(
                                                    "Last terminal input: \(lastInputAt.formatted(date: .abbreviated, time: .standard))"
                                                )
                                        } else {
                                            Text("Never")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .help("No terminal input recorded")
                                        }
                                    }
                                    if let branchName = item.branchName {
                                        Label(branchName, systemImage: "arrow.triangle.branch")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .help("Git branch: \(branchName)")
                                    }
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
                                .background(
                                    index == selectedIndex
                                        ? Color.primary.opacity(0.1)
                                        : Color.clear
                                )
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

    private func relativeInputTimeLabel(_ date: Date, relativeTo referenceDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}
