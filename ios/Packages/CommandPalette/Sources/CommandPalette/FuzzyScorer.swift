import Foundation

/// Sublime Text–style subsequence fuzzy scorer.
///
/// Scoring rules (higher = better match):
/// 1. Empty query → `maxScore` (show everything).
/// 2. Exact full match → `maxScore`.
/// 3. Exact prefix → high bonus.
/// 4. Consecutive character run → bonus per run length.
/// 5. Word-boundary start → bonus per matched boundary character.
/// 6. Plain subsequence match → base score.
public enum FuzzyScorer {
    /// Score returned for an empty query or exact match.
    public static let maxScore: Double = 1_000

    // MARK: - Public API

    /// Score `query` against `target`. Returns 0 if no subsequence match.
    public static func score(query: String, against target: String) -> Double {
        guard !query.isEmpty else { return maxScore }
        guard !target.isEmpty else { return 0 }

        let q = query.lowercased()
        let t = target.lowercased()

        // Exact match
        if q == t { return maxScore }

        // Exact prefix
        if t.hasPrefix(q) {
            return maxScore * 0.9 + Double(q.count) * 2
        }

        return subsequenceScore(query: q, target: t, original: target)
    }

    /// Filter and rank `items` against `query`, returning items in descending score order.
    /// Items scoring 0 are excluded (unless query is empty, in which case all items pass).
    public static func filterAndRank<T>(
        query: String,
        items: [T],
        keyPath: KeyPath<T, String>
    ) -> [T] {
        if query.isEmpty { return items }

        return items
            .compactMap { item -> (T, Double)? in
                let s = score(query: query, against: item[keyPath: keyPath])
                return s > 0 ? (item, s) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    // MARK: - Private subsequence scoring

    private static func subsequenceScore(query: String, target: String, original: String) -> Double {
        let qChars = Array(query)
        let tChars = Array(target)
        let oChars = Array(original) // for boundary detection using original casing

        var qi = 0
        var score: Double = 0
        var lastMatchIndex: Int = -2
        var consecutiveRun = 0

        for (ti, tc) in tChars.enumerated() {
            guard qi < qChars.count else { break }
            if tc == qChars[qi] {
                // Base match point
                score += 1

                // Consecutive bonus
                if ti == lastMatchIndex + 1 {
                    consecutiveRun += 1
                    score += Double(consecutiveRun) * 3
                } else {
                    consecutiveRun = 0
                }

                // Word boundary bonus — character follows a space, hyphen, colon or is first char
                let isWordBoundary: Bool
                if ti == 0 {
                    isWordBoundary = true
                } else {
                    let prev = oChars[ti - 1]
                    isWordBoundary = prev == " " || prev == "-" || prev == ":" || prev == "_"
                        || (prev.isLowercase && oChars[ti].isUppercase) // camelCase
                }
                if isWordBoundary { score += 5 }

                lastMatchIndex = ti
                qi += 1
            }
        }

        // All query characters must appear in order
        guard qi == qChars.count else { return 0 }

        return score
    }
}
