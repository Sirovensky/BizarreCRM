import Testing
@testable import CommandPalette

@Suite("FuzzyScorer")
struct FuzzyScorerTests {

    // MARK: - Exact prefix match

    @Test("exact prefix yields highest score")
    func exactPrefixOutranksSubsequence() {
        let prefix = FuzzyScorer.score(query: "tick", against: "New Ticket")
        let subsequence = FuzzyScorer.score(query: "tick", against: "Stick to Ticket")
        #expect(prefix > subsequence)
    }

    @Test("exact match scores higher than prefix")
    func exactMatchScoresHighest() {
        let exact = FuzzyScorer.score(query: "ticket", against: "ticket")
        let prefix = FuzzyScorer.score(query: "ticket", against: "ticket detail")
        #expect(exact >= prefix)
    }

    // MARK: - Subsequence matching

    @Test("subsequence match returns positive score")
    func subsequenceMatchIsPositive() {
        let score = FuzzyScorer.score(query: "nwt", against: "New Ticket")
        #expect(score > 0)
    }

    @Test("non-matching query returns zero")
    func noMatchReturnsZero() {
        let score = FuzzyScorer.score(query: "zzz", against: "New Ticket")
        #expect(score == 0)
    }

    @Test("empty query returns max score")
    func emptyQueryReturnsMaxScore() {
        let score = FuzzyScorer.score(query: "", against: "New Ticket")
        #expect(score == FuzzyScorer.maxScore)
    }

    @Test("empty target returns zero for non-empty query")
    func emptyTargetReturnsZero() {
        let score = FuzzyScorer.score(query: "abc", against: "")
        #expect(score == 0)
    }

    // MARK: - Case insensitivity

    @Test("matching is case-insensitive")
    func caseInsensitive() {
        let lower = FuzzyScorer.score(query: "ticket", against: "Ticket")
        let upper = FuzzyScorer.score(query: "TICKET", against: "ticket")
        #expect(lower > 0)
        #expect(upper > 0)
    }

    // MARK: - Consecutive bonus

    @Test("consecutive characters score higher than scattered")
    func consecutiveScoredHigher() {
        let consecutive = FuzzyScorer.score(query: "cus", against: "Customer")
        let scattered = FuzzyScorer.score(query: "cus", against: "Close Unit Screen")
        #expect(consecutive > scattered)
    }

    // MARK: - Word boundary bonus

    @Test("word boundary match scores higher")
    func wordBoundaryScoresBetter() {
        let boundary = FuzzyScorer.score(query: "sm", against: "Send SMS")
        let mid = FuzzyScorer.score(query: "sm", against: "awesome map")
        #expect(boundary > 0)
        #expect(mid > 0)
    }

    // MARK: - Ranking

    @Test("filter and rank returns items in descending score order")
    func filterAndRankOrder() {
        let items = ["Open POS", "New Ticket", "Clock In", "Find Customer"]
        let ranked = FuzzyScorer.filterAndRank(query: "new", items: items, keyPath: \.self)
        #expect(ranked.first == "New Ticket")
    }

    @Test("filter and rank excludes zero-score items")
    func filterAndRankExcludesNonMatches() {
        let items = ["Open POS", "New Ticket", "Clock In"]
        let ranked = FuzzyScorer.filterAndRank(query: "zzz", items: items, keyPath: \.self)
        #expect(ranked.isEmpty)
    }

    @Test("filter and rank with empty query returns all items")
    func filterAndRankEmptyQueryReturnsAll() {
        let items = ["Open POS", "New Ticket", "Clock In"]
        let ranked = FuzzyScorer.filterAndRank(query: "", items: items, keyPath: \.self)
        #expect(ranked.count == items.count)
    }
}
