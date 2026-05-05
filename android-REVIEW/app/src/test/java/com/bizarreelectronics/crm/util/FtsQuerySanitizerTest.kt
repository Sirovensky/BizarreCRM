package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM-only unit tests for [FtsQuerySanitizer] — §18.3 (prefix matching +
 * Levenshtein typo tolerance).
 */
class FtsQuerySanitizerTest {

    // ── sanitize ─────────────────────────────────────────────────────────────

    @Test fun `sanitize appends star to single token`() {
        assertEquals("iphone*", FtsQuerySanitizer.sanitize("iphone"))
    }

    @Test fun `sanitize lowercases input`() {
        assertEquals("iphone*", FtsQuerySanitizer.sanitize("iPhone"))
    }

    @Test fun `sanitize strips punctuation`() {
        assertEquals("johns* iphone*", FtsQuerySanitizer.sanitize("John's iPhone"))
    }

    @Test fun `sanitize strips special fts chars`() {
        // Unmatched quotes / parens crash FTS4 MATCH
        assertEquals("broken* query*", FtsQuerySanitizer.sanitize("broken\" (query)"))
    }

    @Test fun `sanitize collapses whitespace`() {
        assertEquals("a* b*", FtsQuerySanitizer.sanitize("  a   b  "))
    }

    @Test fun `sanitize returns null for blank input`() {
        assertNull(FtsQuerySanitizer.sanitize(""))
        assertNull(FtsQuerySanitizer.sanitize("   "))
        assertNull(FtsQuerySanitizer.sanitize("(\"'"))
    }

    @Test fun `sanitize preserves digits`() {
        assertEquals("t1042*", FtsQuerySanitizer.sanitize("T-1042"))
    }

    @Test fun `sanitize multi-word prefix tokens`() {
        assertEquals("ready* for*", FtsQuerySanitizer.sanitize("Ready for"))
    }

    // ── withinEditDistance ───────────────────────────────────────────────────

    @Test fun `exact match is distance 0`() {
        assertTrue(FtsQuerySanitizer.withinEditDistance("iphone", "iphone"))
    }

    @Test fun `one typo is distance 1`() {
        // "iphone" vs "iphane" — 1 substitution
        assertTrue(FtsQuerySanitizer.withinEditDistance("iphone", "iphane"))
    }

    @Test fun `two typos is distance 2`() {
        // "samsung" vs "samsumg" — 1 transposition
        assertTrue(FtsQuerySanitizer.withinEditDistance("samsung", "samsumg"))
    }

    @Test fun `three typos exceeds max distance`() {
        assertFalse(FtsQuerySanitizer.withinEditDistance("iphone", "ipad"))
    }

    @Test fun `length difference too large skips dp`() {
        // "ab" vs "abcdefgh" — length diff = 6 > max 2
        assertFalse(FtsQuerySanitizer.withinEditDistance("abcde", "ab"))
    }

    @Test fun `short word skips fuzzy matching`() {
        // Words shorter than MIN_LENGTH_FOR_FUZZY always return false to avoid noise
        assertFalse(FtsQuerySanitizer.withinEditDistance("ab", "ac"))
    }

    @Test fun `insertion is counted`() {
        // "colour" vs "color" — 1 deletion
        assertTrue(FtsQuerySanitizer.withinEditDistance("colour", "color"))
    }

    // ── isFuzzyMatch ─────────────────────────────────────────────────────────

    @Test fun `isFuzzyMatch returns true when query token matches result token`() {
        val queryWords = listOf("iphone")
        assertTrue(FtsQuerySanitizer.isFuzzyMatch(queryWords, "iphone 14 screen replacement"))
    }

    @Test fun `isFuzzyMatch returns true on one-typo match`() {
        val queryWords = listOf("iphane")
        assertTrue(FtsQuerySanitizer.isFuzzyMatch(queryWords, "iphone 14 screen replacement"))
    }

    @Test fun `isFuzzyMatch returns false when no token is close enough`() {
        val queryWords = listOf("samsung")
        assertFalse(FtsQuerySanitizer.isFuzzyMatch(queryWords, "iphone 14 screen replacement"))
    }

    @Test fun `isFuzzyMatch skips short query words`() {
        // "ok" has length 2 < MIN_LENGTH_FOR_FUZZY — should not trigger a match
        val queryWords = listOf("ok")
        assertFalse(FtsQuerySanitizer.isFuzzyMatch(queryWords, "okay screen"))
    }

    @Test fun `isFuzzyMatch returns false on empty query words`() {
        assertFalse(FtsQuerySanitizer.isFuzzyMatch(emptyList(), "iphone 14"))
    }
}
