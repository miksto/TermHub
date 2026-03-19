import SwiftUI

struct SessionRowView: View {
    let session: TerminalSession

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
        }
    }
}
