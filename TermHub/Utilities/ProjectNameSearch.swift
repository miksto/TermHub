import Foundation

/// Fuzzy matching rules for the sidebar's project search.
enum ProjectNameSearch {
    /// Returns whether a project name matches a search query.
    ///
    /// Character-order matching keeps short queries responsive, while trigram
    /// similarity allows small spelling mistakes in longer queries.
    static func matches(query: String, projectName: String) -> Bool {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return true }

        let normalizedProjectName = normalized(projectName)
        guard !normalizedProjectName.isEmpty else { return false }

        if FuzzyMatch.score(query: normalizedQuery, candidate: normalizedProjectName) != nil {
            return true
        }

        guard normalizedQuery.count >= 3, normalizedProjectName.count >= 3 else {
            return false
        }

        return trigramSimilarity(normalizedQuery, normalizedProjectName) >= 0.55
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return words.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func trigramSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsTrigrams = trigrams(in: lhs)
        let rhsTrigrams = trigrams(in: rhs)
        let sharedCount = lhsTrigrams.intersection(rhsTrigrams).count

        return Double(2 * sharedCount) / Double(lhsTrigrams.count + rhsTrigrams.count)
    }

    private static func trigrams(in value: String) -> Set<String> {
        let characters = Array("  \(value)  ")
        return Set(characters.indices.dropLast(2).map { index in
            String(characters[index...index + 2])
        })
    }
}
