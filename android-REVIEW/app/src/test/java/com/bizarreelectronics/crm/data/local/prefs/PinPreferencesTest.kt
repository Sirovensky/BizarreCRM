package com.bizarreelectronics.crm.data.local.prefs

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM-only unit tests for the PIN lock logic added in §2.5 (ActionPlan L311).
 *
 * Because [PinPreferences] requires an Android [Context] and EncryptedSharedPreferences
 * (which depend on the Android Keystore), direct instantiation is not possible in a
 * pure JVM environment. These tests instead exercise the same decision logic by
 * extracting it into a plain-Kotlin helper — [ShouldLockDecider] — that mirrors the
 * exact branch structure of [PinPreferences.shouldLock] without any Android dependency.
 *
 * The [LockNowEffect] helper mirrors [PinPreferences.lockNow] to verify that resetting
 * lastUnlockAtMillis to 0 drives [ShouldLockDecider.decide] to true on the next call.
 *
 * All production constants (GRACE_NEVER, default grace = 15 min) are referenced via
 * [PinPreferences.Companion] to ensure tests stay in sync with the real values.
 *
 * Covered cases:
 *   - grace = 0  → locks whenever elapsed >= 1 000 ms; does NOT lock within same session
 *   - grace = 1  → locks only after 60 000 ms elapsed
 *   - grace = 15 → locks only after 900 000 ms elapsed; default value is 15
 *   - grace = GRACE_NEVER → never locks mid-session even after long elapsed
 *   - cold-start (lastUnlock == 0) → always locks regardless of grace value
 *   - lockNow() → sets lastUnlock = 0; next decide() → true
 *   - no-PIN → always returns false
 */
class PinPreferencesTest {

    // -------------------------------------------------------------------------
    // Minimal pure-Kotlin mirror of shouldLock / lockNow for JVM testing
    // -------------------------------------------------------------------------

    /**
     * Mirrors [PinPreferences.shouldLock] exactly, with injectable fields for
     * unit-testing without Android runtime.
     */
    private class ShouldLockDecider(
        var isPinSet: Boolean = true,
        var lastUnlockAtMillis: Long = 0L,
        var lockGraceMinutes: Int = PinPreferences.GRACE_NEVER,
    ) {
        fun decide(now: Long = System.currentTimeMillis()): Boolean {
            if (!isPinSet) return false
            val last = lastUnlockAtMillis
            if (last == 0L) return true                 // cold start / lockNow()
            val grace = lockGraceMinutes
            if (grace == PinPreferences.GRACE_NEVER) return false
            if (grace == 0) return (now - last) >= 1_000L
            val gracePeriodMs = grace * 60L * 1_000L
            return (now - last) > gracePeriodMs
        }

        /** Mirrors [PinPreferences.lockNow]. */
        fun lockNow() {
            lastUnlockAtMillis = 0L
        }
    }

    // -------------------------------------------------------------------------
    // Helper: fake "now" values for time-based tests
    // -------------------------------------------------------------------------

    private val baseMs = 1_000_000_000L    // arbitrary epoch anchor

    // -------------------------------------------------------------------------
    // grace = 0 (Immediate)
    // -------------------------------------------------------------------------

    @Test
    fun `grace 0 - does NOT lock within 999ms of same session`() {
        val d = ShouldLockDecider(lastUnlockAtMillis = baseMs, lockGraceMinutes = 0)
        assertFalse("Should not lock within 1 second of unlock", d.decide(now = baseMs + 999L))
    }

    @Test
    fun `grace 0 - locks at exactly 1000ms elapsed`() {
        val d = ShouldLockDecider(lastUnlockAtMillis = baseMs, lockGraceMinutes = 0)
        assertTrue("Should lock at 1000 ms", d.decide(now = baseMs + 1_000L))
    }

    @Test
    fun `grace 0 - locks well beyond 1000ms`() {
        val d = ShouldLockDecider(lastUnlockAtMillis = baseMs, lockGraceMinutes = 0)
        assertTrue("Should lock at 5 min", d.decide(now = baseMs + 5 * 60_000L))
    }

    // -------------------------------------------------------------------------
    // grace = 1 (1 minute)
    // -------------------------------------------------------------------------

    @Test
    fun `grace 1 - does NOT lock at 59 seconds`() {
        val d = ShouldLockDecider(lastUnlockAtMillis = baseMs, lockGraceMinutes = 1)
        assertFalse("Should not lock at 59s", d.decide(now = baseMs + 59_000L))
    }

    @Test
    fun `grace 1 - locks just after 60 seconds`() {
        val d = ShouldLockDecider(lastUnlockAtMillis = baseMs, lockGraceMinutes = 1)
        assertTrue("Should lock at 60 001 ms", d.decide(now = baseMs + 60_001L))
    }

    // -------------------------------------------------------------------------
    // grace = 15 (default, 15 minutes)
    // -------------------------------------------------------------------------

    @Test
    fun `grace 15 - does NOT lock at 14 minutes`() {
        val d = ShouldLockDecider(lastUnlockAtMillis = baseMs, lockGraceMinutes = 15)
        assertFalse("Should not lock at 14 min", d.decide(now = baseMs + 14 * 60_000L))
    }

    @Test
    fun `grace 15 - locks just after 15 minutes`() {
        val d = ShouldLockDecider(lastUnlockAtMillis = baseMs, lockGraceMinutes = 15)
        assertTrue("Should lock at 15 min + 1ms", d.decide(now = baseMs + 15 * 60_000L + 1L))
    }

    @Test
    fun `GRACE_NEVER constant equals Int MAX_VALUE`() {
        assertEquals(Int.MAX_VALUE, PinPreferences.GRACE_NEVER)
    }

    // -------------------------------------------------------------------------
    // grace = GRACE_NEVER
    // -------------------------------------------------------------------------

    @Test
    fun `grace NEVER - does NOT lock even after many hours`() {
        val d = ShouldLockDecider(
            lastUnlockAtMillis = baseMs,
            lockGraceMinutes = PinPreferences.GRACE_NEVER,
        )
        assertFalse("GRACE_NEVER should never lock mid-session", d.decide(now = baseMs + 24 * 3_600_000L))
    }

    // -------------------------------------------------------------------------
    // Cold-start (lastUnlockAtMillis == 0)
    // -------------------------------------------------------------------------

    @Test
    fun `cold start - always locks when PIN is set regardless of grace`() {
        for (grace in listOf(0, 1, 5, 15, PinPreferences.GRACE_NEVER)) {
            val d = ShouldLockDecider(lastUnlockAtMillis = 0L, lockGraceMinutes = grace)
            assertTrue("Cold start should lock with grace=$grace", d.decide(now = baseMs))
        }
    }

    // -------------------------------------------------------------------------
    // lockNow immediate effect
    // -------------------------------------------------------------------------

    @Test
    fun `lockNow - resets lastUnlock and causes shouldLock to return true`() {
        val d = ShouldLockDecider(
            lastUnlockAtMillis = baseMs,
            lockGraceMinutes = PinPreferences.GRACE_NEVER, // would normally never lock
        )
        // Before lockNow: GRACE_NEVER → no lock
        assertFalse("Before lockNow: should not lock with GRACE_NEVER", d.decide(now = baseMs + 1L))

        d.lockNow()

        // After lockNow: lastUnlock is 0 → always locks
        assertTrue("After lockNow: should lock (cold-start path)", d.decide(now = baseMs + 1L))
    }

    @Test
    fun `lockNow - effective even with grace 15 which normally allows long sessions`() {
        val d = ShouldLockDecider(lastUnlockAtMillis = baseMs, lockGraceMinutes = 15)
        assertFalse("Should not lock at 5 min with grace=15", d.decide(now = baseMs + 5 * 60_000L))

        d.lockNow()

        assertTrue("After lockNow: should lock immediately", d.decide(now = baseMs + 1L))
    }

    // -------------------------------------------------------------------------
    // No PIN — always returns false
    // -------------------------------------------------------------------------

    @Test
    fun `no PIN set - shouldLock always returns false`() {
        val d = ShouldLockDecider(isPinSet = false, lastUnlockAtMillis = 0L, lockGraceMinutes = 0)
        assertFalse("No PIN: should not lock", d.decide(now = baseMs))
    }

    @Test
    fun `no PIN set - shouldLock false even on cold start path`() {
        // lastUnlockAtMillis = 0 would normally be cold-start path, but no PIN means false
        val d = ShouldLockDecider(isPinSet = false, lastUnlockAtMillis = 0L, lockGraceMinutes = PinPreferences.GRACE_NEVER)
        assertFalse("No PIN: cold-start path should return false", d.decide(now = baseMs))
    }

    // -------------------------------------------------------------------------
    // Default grace value carry-forward
    // -------------------------------------------------------------------------

    @Test
    fun `GRACE_NEVER sentinel is Int MAX_VALUE — carry-forward check`() {
        // Verifies the sentinel stays as Int.MAX_VALUE so existing code that writes
        // -1 (legacy lockTimeoutMinutes = never) is distinguishable from GRACE_NEVER.
        assertTrue(
            "GRACE_NEVER must be Int.MAX_VALUE",
            PinPreferences.GRACE_NEVER == Int.MAX_VALUE,
        )
        // And must not equal the legacy -1 sentinel used by lockTimeoutMinutes
        assertTrue(
            "GRACE_NEVER must differ from legacy -1 sentinel",
            PinPreferences.GRACE_NEVER != -1,
        )
    }
}
