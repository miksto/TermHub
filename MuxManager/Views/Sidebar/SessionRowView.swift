import SwiftUI

struct SessionRowView: View {
    let session: TerminalSession
    var onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(session.title)
                    .lineLimit(1)
                if let branch = session.branchName {
                    Text(branch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isHovering {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
