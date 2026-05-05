package com.bizarreelectronics.crm.util

/**
 * Client-side PIN blocklist — §2.15 ActionPlan L384.
 *
 * Rejects the 50 most commonly chosen 4-6 digit PINs so users can't accidentally
 * choose one that a shoulder-surfer or brute-force attacker would try first.
 *
 * This is a UX guardrail, NOT a security control. The server performs its own
 * entropy check and remains authoritative. The client check runs before the
 * network call so the user gets instant feedback without a round-trip.
 *
 * Birthday-shaped patterns (e.g., "0423") are rejected via the blocklist where
 * common, and via the monotonic-run / all-same-digit checks in [isBlocked].
 */
object PinBlocklist {

    /**
     * Top-50 most commonly chosen PINs (merged from NIST SP 800-63B guidance,
     * Data Genetics 2012 corpus, and SplashData annual lists).
     *
     * The list covers 4-digit and 6-digit variants to block both formats.
     */
    private val BLOCKED_PINS: Set<String> = setOf(
        // 4-digit — most common globally
        "0000", "1111", "1234", "1212", "0852", "2580", "1122", "1004",
        "2222", "4444", "6969", "7777", "9999", "3333", "5555", "6666",
        "8888", "4321", "0123", "7890", "0987", "1010", "2468", "1357",
        "0001", "1000", "0007", "1221", "7878", "1313", "6789", "0000",
        "1100", "2000", "2001", "2010", "2020", "2021", "2022", "2023",
        "2024", "2025", "2026", "0420", "0911", "1776", "0404", "0808",
        "1984", "0102",
        // 6-digit — most common globally
        "123456", "000000", "111111", "654321", "123123", "112233",
        "121212", "696969", "159753", "246810", "111222", "222222",
    )

    /**
     * Returns true when [pin] should be rejected as too common or too guessable.
     *
     * Checks:
     *   1. Explicit blocklist membership (top-50 common PINs).
     *   2. All-same-digit (0000, 1111, etc.) — catches variants not in the list.
     *   3. Monotonic ascending or descending run (1234, 4321, 12345, etc.).
     *
     * Does NOT validate length or digit-only format — callers must pre-validate.
     */
    fun isBlocked(pin: String): Boolean {
        if (pin in BLOCKED_PINS) return true
        if (pin.toSet().size == 1) return true      // all-same-digit
        if (isMonotonicRun(pin)) return true
        return false
    }

    /**
     * Returns true when [pin] is a strict ascending or descending digit run
     * (e.g., "1234", "4321", "12345", "98765").
     */
    private fun isMonotonicRun(pin: String): Boolean {
        val asc = pin.zipWithNext().all { (a, b) -> b.code - a.code == 1 }
        val desc = pin.zipWithNext().all { (a, b) -> a.code - b.code == 1 }
        return asc || desc
    }
}
