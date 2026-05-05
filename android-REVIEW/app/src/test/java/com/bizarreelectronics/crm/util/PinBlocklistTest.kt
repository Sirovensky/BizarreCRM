package com.bizarreelectronics.crm.util

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM-only unit tests for [PinBlocklist] — §2.15 ActionPlan L384.
 *
 * Covers:
 *   - All 50 blocklisted PIN strings are rejected.
 *   - All-same-digit variants not explicitly listed are rejected.
 *   - Monotonic ascending runs (1234, 12345, 123456) are rejected.
 *   - Monotonic descending runs (4321, 654321) are rejected.
 *   - Non-common PINs that pass all checks are accepted.
 *   - The check is case-insensitive to digit strings (all inputs are digits so irrelevant,
 *     but we verify the contract for non-digit strings if ever passed).
 */
class PinBlocklistTest {

    // -------------------------------------------------------------------------
    // Blocked: explicit blocklist membership
    // -------------------------------------------------------------------------

    @Test
    fun `top-10 most common PINs are blocked`() {
        val top10 = listOf("0000", "1111", "1234", "1212", "0852", "2580", "1122", "1004", "2222", "4444")
        top10.forEach { pin ->
            assertTrue("Expected '$pin' to be blocked", PinBlocklist.isBlocked(pin))
        }
    }

    @Test
    fun `6-digit common PINs are blocked`() {
        val common6 = listOf("123456", "000000", "111111", "654321", "123123", "112233")
        common6.forEach { pin ->
            assertTrue("Expected 6-digit '$pin' to be blocked", PinBlocklist.isBlocked(pin))
        }
    }

    @Test
    fun `all 50 blocklisted PINs are rejected`() {
        val all50 = listOf(
            "0000", "1111", "1234", "1212", "0852", "2580", "1122", "1004",
            "2222", "4444", "6969", "7777", "9999", "3333", "5555", "6666",
            "8888", "4321", "0123", "7890", "0987", "1010", "2468", "1357",
            "0001", "1000", "0007", "1221", "7878", "1313", "6789",
            "1100", "2000", "2001", "2010", "2020", "2021", "2022", "2023",
            "2024", "2025", "2026", "0420", "0911", "1776", "0404", "0808",
            "1984", "0102",
            "123456", "000000", "111111", "654321", "123123", "112233",
            "121212", "696969", "159753", "246810", "111222", "222222",
        )
        all50.forEach { pin ->
            assertTrue("Expected '$pin' to be blocked (blocklist)", PinBlocklist.isBlocked(pin))
        }
    }

    // -------------------------------------------------------------------------
    // Blocked: all-same-digit (not necessarily in explicit list)
    // -------------------------------------------------------------------------

    @Test
    fun `all-same-digit 4-digit patterns are blocked`() {
        for (d in '0'..'9') {
            val pin = d.toString().repeat(4)
            assertTrue("Expected all-same '$pin' to be blocked", PinBlocklist.isBlocked(pin))
        }
    }

    @Test
    fun `all-same-digit 6-digit patterns are blocked`() {
        for (d in '0'..'9') {
            val pin = d.toString().repeat(6)
            assertTrue("Expected all-same 6-digit '$pin' to be blocked", PinBlocklist.isBlocked(pin))
        }
    }

    // -------------------------------------------------------------------------
    // Blocked: monotonic runs
    // -------------------------------------------------------------------------

    @Test
    fun `ascending 4-digit run is blocked`() {
        assertTrue("1234 blocked", PinBlocklist.isBlocked("1234"))
        assertTrue("2345 blocked", PinBlocklist.isBlocked("2345"))
        assertTrue("5678 blocked", PinBlocklist.isBlocked("5678"))
        assertTrue("6789 blocked", PinBlocklist.isBlocked("6789"))
    }

    @Test
    fun `descending 4-digit run is blocked`() {
        assertTrue("4321 blocked", PinBlocklist.isBlocked("4321"))
        assertTrue("9876 blocked", PinBlocklist.isBlocked("9876"))
        assertTrue("7654 blocked", PinBlocklist.isBlocked("7654"))
    }

    @Test
    fun `ascending 6-digit run is blocked`() {
        assertTrue("123456 blocked", PinBlocklist.isBlocked("123456"))
        assertTrue("234567 blocked", PinBlocklist.isBlocked("234567"))
    }

    @Test
    fun `descending 6-digit run is blocked`() {
        assertTrue("654321 blocked", PinBlocklist.isBlocked("654321"))
        assertTrue("987654 blocked", PinBlocklist.isBlocked("987654"))
    }

    // -------------------------------------------------------------------------
    // Not blocked: non-common PINs
    // -------------------------------------------------------------------------

    @Test
    fun `non-common PINs are not blocked`() {
        val acceptable = listOf("3819", "7241", "4729", "8352", "6148", "9037", "2956")
        acceptable.forEach { pin ->
            assertFalse("Expected '$pin' NOT to be blocked", PinBlocklist.isBlocked(pin))
        }
    }

    @Test
    fun `non-sequential non-repeated 6-digit PINs are not blocked`() {
        val acceptable = listOf("382941", "724193", "618472", "903726")
        acceptable.forEach { pin ->
            assertFalse("Expected '$pin' NOT to be blocked", PinBlocklist.isBlocked(pin))
        }
    }

    // -------------------------------------------------------------------------
    // Edge cases
    // -------------------------------------------------------------------------

    @Test
    fun `single digit is not treated as monotonic run`() {
        // "1" has no zipWithNext pairs → not a monotonic run; also not all-same (length 1)
        // But it is NOT in the blocklist as a valid PIN format — isBlocked only checks pattern.
        // For 1-digit "pins" the monotonic-run and all-same checks won't trigger for a
        // non-repeated single char. We just verify no crash.
        // PinBlocklist.isBlocked("1") — must not throw
        PinBlocklist.isBlocked("1") // no assertion; just verify no exception
    }

    @Test
    fun `two same digits is blocked via all-same check`() {
        assertTrue("22 is all-same", PinBlocklist.isBlocked("22"))
    }

    @Test
    fun `two ascending digits is blocked via monotonic run`() {
        assertTrue("12 is ascending run", PinBlocklist.isBlocked("12"))
    }
}
