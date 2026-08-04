import AppKit
import SwiftUI

struct GitCommitHistoryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)))
    }

    private var header: some View {
        HStack {
            Text("Commits")
                .font(.headline)
            Spacer()
            Button {
                appState.refreshCommitHistory()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh commits")
            .disabled(appState.isCommitHistoryLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if appState.isCommitHistoryLoading {
            ProgressView("Loading commits…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch appState.currentCommitHistory {
            case .idle:
                Color.clear
            case .unavailable(let message):
                ContentUnavailableView("Commit History Unavailable", systemImage: "arrow.triangle.branch", description: Text(message))
            case .failed(let message):
                ContentUnavailableView("Couldn't Load Commits", systemImage: "exclamationmark.triangle", description: Text(message))
            case .loaded(let commits):
                if commits.isEmpty {
                    ContentUnavailableView("No Commits", systemImage: "clock", description: Text("This branch has no commits to display."))
                } else {
                    HSplitView {
                        commitDiff
                            .frame(minWidth: 180)
                        commitList(commits)
                            .frame(minWidth: 180)
                    }
                }
            }
        }
    }

    private func commitList(_ commits: [GitCommit]) -> some View {
        List(commits) { commit in
            HStack(alignment: .top, spacing: 10) {
                Text(commit.shortHash)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tint)
                    .frame(width: 62, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(commit.messagePreview)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(commit.authorName) · \(commit.authoredDate.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commit.hash, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy full commit SHA")
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
            .background(appState.selectedCommit?.hash == commit.hash ? Color.accentColor.opacity(0.16) : .clear)
            .onTapGesture {
                appState.selectCommit(commit)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var commitDiff: some View {
        if let commit = appState.selectedCommit {
            VStack(alignment: .leading, spacing: 0) {
                Text("Diff for \(commit.shortHash)")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
                if appState.isSelectedCommitDiffLoading {
                    ProgressView("Loading diff…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = appState.selectedCommitDiffError {
                    ContentUnavailableView("Couldn't Load Diff", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if let diff = appState.selectedCommitDiff, !diff.files.isEmpty {
                    DiffTableView(diff: diff, workingDirectory: appState.selectedSessionGitPath ?? "")
                } else {
                    ContentUnavailableView("No File Changes", systemImage: "doc", description: Text("This commit has no diff to display."))
                }
            }
        } else {
            ContentUnavailableView("Select a Commit", systemImage: "clock.arrow.circlepath", description: Text("Select a commit to inspect its diff."))
        }
    }
}
