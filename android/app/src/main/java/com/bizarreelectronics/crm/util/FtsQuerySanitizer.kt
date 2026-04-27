package com.bizarreelectronics.crm.util

/**
 * Utilities for §18 (Search) — FTS4 query preparation and optional Levenshtein
 * post-filtering.
 *
 * ## FTS query sanitization (§18.3 — prefix matching + custom tokenizer)
 *
 * FTS4 uses a simple tokenizer that splits on whitespace and punctuation.
 * Raw user input may contain characters that crash the MATCH expression
 * (e.g. `"(`, `"`, `*`) so we normalise before hitting the DB:
 *
 *  1. Lowercase the string.
 *  2. Strip characters not in `[a-z0-9 ]` (letters, digits, spaces).
 *  3. Collapse multiple spaces to one.
 *  4. Append `*` to every token so prefix matching is implicit.
 *
 * Example: `"John's iPhone"` → `"john* iphone*"` which matches
 * "John Doe", "Johnny", "iPhone 14", "iPhone screen", etc.
 *
 * ## Levenshtein post-filter (§18.3 — typo tolerance, edit distance ≤ 2)
 *
 * SQLite FTS4 does not have built-in fuzzy matching. After retrieving FTS results
 * for the normalised query we apply a Kotlin-side Levenshtein gate on the raw user
 * input against each result's text tokens. A result survives the filter if *any*
 * token in its combined text is within [maxEditDistance] of *any* query word that
 * is at least [minLengthForFuzzy] characters long.
 *
 * This is intentionally conservative:
 *  - FTS already handles exact/prefix — Levenshtein only supplements with typo
 *    recovery for long-enough words.
 *  - Results from FTS prefix matching always pass (the FTS hit is sufficient
 *    evidence of relevance). The Levenshtein filter is applied to the
 *    **complement** — items that did NOT match FTS but were retrieved by a
 *    broader LIKE fallback when FTS returns nothing.
 */
object FtsQuerySanitizer {

    private val STRIP_REGEX = Regex("[^a-z0-9 ]")
    private val MULTI_SPACE = Regex("\\s+")

    /**
     * Normalize a raw user query into an FTS4-safe MATCH expression with
     * trailing `*` on every token for prefix matching.
     *
     * Returns null if the cleaned string is blank (caller should skip FTS and
     * use the LIKE fallback).
     */
    fun sanitize(raw: String): String? {
        val cleaned = raw
            .lowercase()
            .replace(STRIP_REGEX, " ")
            .replace(MULTI_SPACE, " ")
            .trim()
        if (cleaned.isBlank()) return null
        // Append * to each token for prefix matching
        return cleaned.split(' ').filter { it.isNotEmpty() }.joinToString(" ") { "$it*" }
    }

    // ── Levenshtein (§18.3, edit distance ≤ 2 on words ≥ 4 chars) ──────────

    /**
     * Minimum word length (chars) before Levenshtein fuzzy matching is applied.
     * Short tokens like "to", "by" produce too many false positives.
     */
    const val MIN_LENGTH_FOR_FUZZY = 4

    /**
     * Maximum allowed edit distance (insertions + deletions + substitutions).
     */
    const val MAX_EDIT_DISTANCE = 2

    /**
     * Returns `true` if [candidate] is within [maxEditDistance] edits of [target].
     * Uses the standard Wagner-Fischer DP algorithm in O(m·n) time.
     */
    fun withinEditDistance(
        target: String,
        candidate: String,
        maxEditDistance: Int = MAX_EDIT_DISTANCE,
    ): Boolean {
        if (target.length < MIN_LENGTH_FOR_FUZZY) return false
        val m = target.length
        val n = candidate.length
        // Early exit if length difference alone exceeds the budget
        if (kotlin.math.abs(m - n) > maxEditDistance) return false

        // dp[i][j] = edit distance between target[0..i) and candidate[0..j)
        val dp = Array(m + 1) { IntArray(n + 1) }
        for (i in 0..m) dp[i][0] = i
        for (j in 0..n) dp[0][j] = j
        for (i in 1..m) {
            for (j in 1..n) {
                val cost = if (target[i - 1] == candidate[j - 1]) 0 else 1
                dp[i][j] = minOf(
                    dp[i - 1][j] + 1,          // deletion
                    dp[i][j - 1] + 1,           // insertion
                    dp[i - 1][j - 1] + cost,    // substitution
                )
            }
        }
        return dp[m][n] <= maxEditDistance
    }

    /**
     * Check whether any token in [resultText] is within the fuzzy edit distance
     * of any word in [queryWords]. Used as a post-filter on LIKE-fallback results.
     *
     * [resultText] should be the combined searchable text for a single entity
     * (e.g. "John Doe johndoe@example.com 5555551234" for a customer).
     */
    fun isFuzzyMatch(queryWords: List<String>, resultText: String): Boolean {
        val resultTokens = resultText.lowercase().split(MULTI_SPACE).filter { it.length >= MIN_LENGTH_FOR_FUZZY }
        return queryWords
            .filter { it.length >= MIN_LENGTH_FOR_FUZZY }
            .any { queryWord ->
                resultTokens.any { token -> withinEditDistance(queryWord, token) }
            }
    }
}
