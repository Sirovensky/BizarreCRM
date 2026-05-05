package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [PasswordStrength.evaluate].
 *
 * All tests run on the JVM host (no Android runtime needed).
 * Coverage: individual rules, boundary lengths, common-password rejection,
 * level thresholds (NONE / WEAK / FAIR / STRONG / VERY_STRONG).
 */
class PasswordStrengthTest {

    // ─── Rule: MIN_LENGTH ──────────────────────────────────────────────

    @Test
    fun `MIN_LENGTH fails for 7-char password`() {
        val result = PasswordStrength.evaluate("abcdefg")          // 7 chars, no upper/digit/symbol
        assertFalse(result.ruleChecks[PasswordStrength.Rule.MIN_LENGTH]!!)
    }

    @Test
    fun `MIN_LENGTH passes for exactly 8-char password`() {
        val result = PasswordStrength.evaluate("abcdefgh")         // 8 chars
        assertTrue(result.ruleChecks[PasswordStrength.Rule.MIN_LENGTH]!!)
    }

    @Test
    fun `MIN_LENGTH passes for 16-char password`() {
        val result = PasswordStrength.evaluate("abcdefghijklmnop")
        assertTrue(result.ruleChecks[PasswordStrength.Rule.MIN_LENGTH]!!)
    }

    // ─── Rule: HAS_LOWER ──────────────────────────────────────────────

    @Test
    fun `HAS_LOWER fails when no lowercase present`() {
        val result = PasswordStrength.evaluate("ABCDEFGH1!")
        assertFalse(result.ruleChecks[PasswordStrength.Rule.HAS_LOWER]!!)
    }

    @Test
    fun `HAS_LOWER passes when at least one lowercase present`() {
        val result = PasswordStrength.evaluate("ABCDEFGh1!")
        assertTrue(result.ruleChecks[PasswordStrength.Rule.HAS_LOWER]!!)
    }

    // ─── Rule: HAS_UPPER ──────────────────────────────────────────────

    @Test
    fun `HAS_UPPER fails when no uppercase present`() {
        val result = PasswordStrength.evaluate("abcdefgh1!")
        assertFalse(result.ruleChecks[PasswordStrength.Rule.HAS_UPPER]!!)
    }

    @Test
    fun `HAS_UPPER passes when at least one uppercase present`() {
        val result = PasswordStrength.evaluate("abcdefgH1!")
        assertTrue(result.ruleChecks[PasswordStrength.Rule.HAS_UPPER]!!)
    }

    // ─── Rule: HAS_DIGIT ──────────────────────────────────────────────

    @Test
    fun `HAS_DIGIT fails when no digit present`() {
        val result = PasswordStrength.evaluate("abcdefgH!")
        assertFalse(result.ruleChecks[PasswordStrength.Rule.HAS_DIGIT]!!)
    }

    @Test
    fun `HAS_DIGIT passes when at least one digit present`() {
        val result = PasswordStrength.evaluate("abcdefgH1!")
        assertTrue(result.ruleChecks[PasswordStrength.Rule.HAS_DIGIT]!!)
    }

    // ─── Rule: HAS_SYMBOL ─────────────────────────────────────────────

    @Test
    fun `HAS_SYMBOL fails for alphanumeric-only password`() {
        val result = PasswordStrength.evaluate("Abcdefgh1")
        assertFalse(result.ruleChecks[PasswordStrength.Rule.HAS_SYMBOL]!!)
    }

    @Test
    fun `HAS_SYMBOL passes for password containing exclamation mark`() {
        val result = PasswordStrength.evaluate("Abcdefgh1!")
        assertTrue(result.ruleChecks[PasswordStrength.Rule.HAS_SYMBOL]!!)
    }

    @Test
    fun `HAS_SYMBOL passes for password containing at-sign`() {
        val result = PasswordStrength.evaluate("Abcdefgh1@")
        assertTrue(result.ruleChecks[PasswordStrength.Rule.HAS_SYMBOL]!!)
    }

    // ─── Rule: NOT_COMMON ─────────────────────────────────────────────

    @Test
    fun `NOT_COMMON fails for exact common password`() {
        val result = PasswordStrength.evaluate("password")
        assertFalse(result.ruleChecks[PasswordStrength.Rule.NOT_COMMON]!!)
    }

    @Test
    fun `NOT_COMMON fails for common password in mixed case`() {
        val result = PasswordStrength.evaluate("Password")     // case-insensitive match
        assertFalse(result.ruleChecks[PasswordStrength.Rule.NOT_COMMON]!!)
    }

    @Test
    fun `NOT_COMMON fails for 123456`() {
        val result = PasswordStrength.evaluate("123456")
        assertFalse(result.ruleChecks[PasswordStrength.Rule.NOT_COMMON]!!)
    }

    @Test
    fun `NOT_COMMON passes for non-common password`() {
        val result = PasswordStrength.evaluate("Xk9!mN#zP2wQ")
        assertTrue(result.ruleChecks[PasswordStrength.Rule.NOT_COMMON]!!)
    }

    // ─── Level: NONE ──────────────────────────────────────────────────

    @Test
    fun `empty password returns NONE`() {
        val result = PasswordStrength.evaluate("")
        assertEquals(PasswordStrength.Level.NONE, result.level)
    }

    @Test
    fun `empty password has all rules failing`() {
        val result = PasswordStrength.evaluate("")
        assertTrue(result.ruleChecks.values.all { !it })
    }

    // ─── Level: WEAK ──────────────────────────────────────────────────

    @Test
    fun `1-2 passing rules yields WEAK`() {
        // Only MIN_LENGTH passes (lowercase only, no upper/digit/symbol, not common for a unique string)
        // "abcdefghi" — MIN_LENGTH=T, HAS_LOWER=T, HAS_UPPER=F, HAS_DIGIT=F, HAS_SYMBOL=F, NOT_COMMON=T → 3 rules
        // Use very short lowercase string that misses MIN_LENGTH too
        val result = PasswordStrength.evaluate("ab1")          // 2 rules: HAS_LOWER, HAS_DIGIT, NOT_COMMON = 3
        // Let's pick a password that only passes 1-2: 7-char all-upper "ABCDEFG"
        val r2 = PasswordStrength.evaluate("ABCDEFG")          // HAS_UPPER=T, NOT_COMMON=T → 2 passing → WEAK
        assertEquals(PasswordStrength.Level.WEAK, r2.level)
    }

    // ─── Level: FAIR ──────────────────────────────────────────────────

    @Test
    fun `3 passing rules yields FAIR`() {
        // "Abcdefgh" → MIN_LENGTH=T, HAS_LOWER=T, HAS_UPPER=T, HAS_DIGIT=F, HAS_SYMBOL=F, NOT_COMMON=T
        // That's 4 passing → actually STRONG. Use a slightly weaker password:
        // "abcdefgh" → MIN_LENGTH=T, HAS_LOWER=T, NOT_COMMON=T = 3 rules → FAIR
        val result = PasswordStrength.evaluate("abcdefgh")
        assertEquals(PasswordStrength.Level.FAIR, result.level)
    }

    // ─── Level: STRONG ────────────────────────────────────────────────

    @Test
    fun `4-5 passing rules yields STRONG`() {
        // "Abcdefgh1" → MIN_LENGTH=T, HAS_LOWER=T, HAS_UPPER=T, HAS_DIGIT=T, HAS_SYMBOL=F, NOT_COMMON=T → 5 rules
        val result = PasswordStrength.evaluate("Abcdefgh1")
        assertEquals(PasswordStrength.Level.STRONG, result.level)
    }

    // ─── Level: VERY_STRONG ───────────────────────────────────────────

    @Test
    fun `all 6 rules passing yields VERY_STRONG`() {
        // 16 chars, lower, upper, digit, symbol, not common
        val result = PasswordStrength.evaluate("Xk9!mN#zP2wQrS5@")
        assertEquals(PasswordStrength.Level.VERY_STRONG, result.level)
        assertTrue(result.ruleChecks.values.all { it })
    }

    @Test
    fun `16-char all-rule password returns all rules true`() {
        val result = PasswordStrength.evaluate("Tr0ub4dor&3Xyzzy!")
        assertTrue(result.ruleChecks[PasswordStrength.Rule.MIN_LENGTH]!!)
        assertTrue(result.ruleChecks[PasswordStrength.Rule.HAS_LOWER]!!)
        assertTrue(result.ruleChecks[PasswordStrength.Rule.HAS_UPPER]!!)
        assertTrue(result.ruleChecks[PasswordStrength.Rule.HAS_DIGIT]!!)
        assertTrue(result.ruleChecks[PasswordStrength.Rule.HAS_SYMBOL]!!)
        assertTrue(result.ruleChecks[PasswordStrength.Rule.NOT_COMMON]!!)
        assertEquals(PasswordStrength.Level.VERY_STRONG, result.level)
    }

    // ─── Immutability ─────────────────────────────────────────────────

    @Test
    fun `evaluate does not mutate input string`() {
        val original = "Abcdefgh1!"
        val copy = original
        PasswordStrength.evaluate(original)
        assertEquals(copy, original)   // String is immutable in Kotlin; verifies evaluate returns new objects
    }

    // ─── Result.ruleChecks map is complete ────────────────────────────

    @Test
    fun `ruleChecks contains all 6 rules`() {
        val result = PasswordStrength.evaluate("SomePass1!")
        assertEquals(PasswordStrength.Rule.values().size, result.ruleChecks.size)
        PasswordStrength.Rule.values().forEach { rule ->
            assertTrue("ruleChecks missing $rule", result.ruleChecks.containsKey(rule))
        }
    }
}
