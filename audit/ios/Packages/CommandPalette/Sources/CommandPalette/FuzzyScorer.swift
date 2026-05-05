import Foundation

/// Sublime Text–style subsequence fuzzy scorer.
///
/// Scoring rules (higher = better match):
/// 1. Empty query → `maxScore` (show everything).
/// 2. Exact full match → `maxScore`.
/// 3. Exact prefix → high bonus.
/// 4. Consecutive character run → bonus per run length.
/// 5. Word-boundary start → bonus per matched boundary character.
/// 6. Acronym match — query matches the first letter of each word → bonus.
/// 7. Plain subsequence match → base score.
/// 8. Position-in-string penalty — later-position first matches score lower.
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

        // Acronym match — query chars match the first letter of each word
        // e.g. "nt" matches "New Ticket", "oi" matches "Open Inventory"
        if let acronymScore = acronymScore(query: q, target: t) {
            let subScore = subsequenceScore(query: q, target: t, original: target)
            return max(acronymScore, subScore)
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

    // MARK: - Private acronym scoring

    /// Returns a score when `query` is a strict acronym of `target` (each query
    /// character matches the first letter of consecutive words), nil otherwise.
    private static func acronymScore(query: String, target: String) -> Double? {
        // Build word-initial characters of the target
        var initials: [Character] = []
        var prevWasBoundary = true
        for ch in target {
            if ch == " " || ch == "-" || ch == "_" || ch == ":" {
                prevWasBoundary = true
            } else {
                if prevWasBoundary {
                    initials.append(ch)
                }
                prevWasBoundary = false
            }
        }
        guard initials.count >= query.count else { return nil }

        let qChars = Array(query)
        var ii = 0
        for init_ch in initials {
            guard ii < qChars.count else { break }
            if init_ch == qChars[ii] { ii += 1 }
        }
        guard ii == qChars.count else { return nil }

        // Reward pure acronym match: high base + per-char boundary bonus
        return 80 + Double(query.count) * 8
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

        // Position penalty: first match occurring late in the string scores lower.
        // This prevents "re" scoring the same on "Reports: Revenue" (position 0)
        // and "Settings: Revenue" (position 10).
        if lastMatchIndex >= 0 {
            let positionPenalty = Double(tChars.count - qi) * 0.05
            score = max(0, score - positionPenalty)
        }

        return score
    }
}
