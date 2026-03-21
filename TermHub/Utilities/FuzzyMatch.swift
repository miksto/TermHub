import Foundation

enum FuzzyMatch {
    /// Returns a score if all characters of `query` appear in order in `candidate` (case-insensitive).
    /// Returns `nil` if there is no match.
    /// Higher scores indicate better matches.
    static func score(query: String, candidate: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        let queryChars = Array(query.lowercased())
        let candidateChars = Array(candidate.lowercased())
        let candidateOriginal = Array(candidate)

        var queryIndex = 0
        var score = 0
        var lastMatchIndex = -1

        for (i, char) in candidateChars.enumerated() {
            guard queryIndex < queryChars.count else { break }
            if char == queryChars[queryIndex] {
                score += 1

                // Bonus: match at the very start of the candidate
                if i == 0 {
                    score += 3
                }

                // Bonus: word boundary (preceded by space, hyphen, slash, underscore, or uppercase transition)
                if i > 0 {
                    let prev = candidateChars[i - 1]
                    let isWordBoundary = prev == " " || prev == "-" || prev == "/" || prev == "_" || prev == "."
                    let isUpperTransition = candidateOriginal[i].isUppercase && !candidateOriginal[i - 1].isUppercase
                    if isWordBoundary || isUpperTransition {
                        score += 10
                    }
                }

                // Bonus: consecutive match
                if lastMatchIndex == i - 1 {
                    score += 5
                }

                lastMatchIndex = i
                queryIndex += 1
            }
        }

        // All query characters must be matched
        guard queryIndex == queryChars.count else { return nil }
        return score
    }
}
