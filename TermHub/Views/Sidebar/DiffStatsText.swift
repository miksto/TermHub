import SwiftUI

struct DiffStatsText: View {
    let status: GitStatus

    var body: some View {
        (Text("+\(status.linesAdded)").foregroundColor(.green)
            + Text(",").foregroundColor(.secondary)
            + Text("−\(status.linesDeleted)").foregroundColor(.red))
            .font(.system(.caption2, design: .monospaced))
    }
}
