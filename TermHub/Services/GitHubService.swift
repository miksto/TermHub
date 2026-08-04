import Foundation

struct PullRequestLookupService: Sendable {
    var openPullRequestURL: @Sendable (_ repositoryPath: String) -> URL?

    static let live = PullRequestLookupService { repositoryPath in
        GitHubService.openPullRequestURL(repositoryPath: repositoryPath)
    }

    static let unavailable = PullRequestLookupService { _ in nil }
}

enum GitHubService {
    nonisolated(unsafe) static var commandRunner: CommandRunner = ProcessCommandRunner()
    nonisolated(unsafe) static var ghPathOverride: String?

    private struct PullRequest: Decodable {
        let state: String
        let url: URL
    }

    static func openPullRequestURL(repositoryPath: String) -> URL? {
        guard let ghPath = ghPathOverride ?? resolveGitHubCLIPath() else { return nil }

        let result = commandRunner.run(
            executablePath: ghPath,
            arguments: ["pr", "view", "--json", "state,url"],
            environment: ShellEnvironment.shellEnvironment,
            currentDirectoryURL: URL(fileURLWithPath: repositoryPath, isDirectory: true)
        )
        guard result.exitCode == 0,
              let data = result.output.data(using: .utf8),
              let pullRequest = try? JSONDecoder().decode(PullRequest.self, from: data),
              pullRequest.state.uppercased() == "OPEN",
              pullRequest.url.scheme?.lowercased() == "https"
        else { return nil }

        return pullRequest.url
    }

    private static func resolveGitHubCLIPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]
        if let candidate = candidates.first(where: FileManager.default.fileExists(atPath:)) {
            return candidate
        }

        let result = commandRunner.run(
            executablePath: "/usr/bin/which",
            arguments: ["gh"],
            environment: ShellEnvironment.shellEnvironment
        )
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !path.isEmpty ? path : nil
    }
}
