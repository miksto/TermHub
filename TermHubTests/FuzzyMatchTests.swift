import Foundation
import Testing
@testable import TermHub

@Suite("FuzzyMatch Tests")
struct FuzzyMatchTests {

    @Test("empty query matches everything with score 0")
    func emptyQuery() {
        #expect(FuzzyMatch.score(query: "", candidate: "anything") == 0)
    }

    @Test("exact match returns positive score")
    func exactMatch() {
        let score = FuzzyMatch.score(query: "hello", candidate: "hello")
        #expect(score != nil)
        #expect(score! > 0)
    }

    @Test("case-insensitive matching")
    func caseInsensitive() {
        let score = FuzzyMatch.score(query: "hello", candidate: "HELLO")
        #expect(score != nil)
    }

    @Test("subsequence match works")
    func subsequenceMatch() {
        let score = FuzzyMatch.score(query: "hlo", candidate: "hello")
        #expect(score != nil)
    }

    @Test("non-matching returns nil")
    func noMatch() {
        #expect(FuzzyMatch.score(query: "xyz", candidate: "hello") == nil)
    }

    @Test("query longer than candidate returns nil")
    func queryLongerThanCandidate() {
        #expect(FuzzyMatch.score(query: "abcdef", candidate: "abc") == nil)
    }

    @Test("start-of-string bonus increases score")
    func startOfStringBonus() {
        let startScore = FuzzyMatch.score(query: "a", candidate: "apple")!
        let midScore = FuzzyMatch.score(query: "p", candidate: "apple")!
        #expect(startScore > midScore)
    }

    @Test("word boundary bonus increases score")
    func wordBoundaryBonus() {
        let boundaryScore = FuzzyMatch.score(query: "s", candidate: "my-shell")!
        let midWordScore = FuzzyMatch.score(query: "h", candidate: "my-shell")!
        #expect(boundaryScore > midWordScore)
    }

    @Test("consecutive match bonus increases score")
    func consecutiveBonus() {
        let consecutiveScore = FuzzyMatch.score(query: "he", candidate: "hello")!
        let nonConsecutiveScore = FuzzyMatch.score(query: "hl", candidate: "hello")!
        #expect(consecutiveScore > nonConsecutiveScore)
    }

    @Test("camelCase boundary detected")
    func camelCaseBoundary() {
        let score = FuzzyMatch.score(query: "cps", candidate: "commandPaletteState")
        #expect(score != nil)
        #expect(score! > 0)
    }

    @Test("dot separator acts as word boundary")
    func dotBoundary() {
        let score = FuzzyMatch.score(query: "m", candidate: "file.md")
        #expect(score != nil)
    }

    @Test("better match scores higher")
    func betterMatchScoresHigher() {
        let exactPrefix = FuzzyMatch.score(query: "term", candidate: "terminal")!
        let scattered = FuzzyMatch.score(query: "term", candidate: "the_remote_machine")!
        #expect(exactPrefix > scattered)
    }
}
