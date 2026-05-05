package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [SessionTimeoutCore] (and the [SessionTimeout.forTest] factory).
 *
 * Uses a mutable fake clock ([FakeClock]) injected via [SessionTimeout.forTest]
 * so every test is deterministic and executes synchronously without coroutines.
 * The background ticker is bypassed by calling [SessionTimeoutCore.tick] directly.
 *
 * Coverage:
 *   - Config validation (min/max constraints)
 *   - onActivity resets the inactivity timer
 *   - Warning window calculation and countdown
 *   - Level transitions: None → Biometric at 15 m, → Password at 4 h, → Full at 30 d
 *   - requireReAuthNow forces an immediate level change
 *   - clear() resets state and resets lastActivityMs
 *   - onAppBackground / onAppForeground do not reset the inactivity timer
 *   - Sovereignty: tick() is a no-op when isLoggedIn is false
 */
class SessionTimeoutTest {

    // -------------------------------------------------------------------------
    // Fake clock helper
    // -------------------------------------------------------------------------

    private class FakeClock(var nowMs: Long = 0L) {
        val provider: () -> Long = { nowMs }
    }

    // -------------------------------------------------------------------------
    // Convenience factory
    // -------------------------------------------------------------------------

    private fun make(
        clock: FakeClock = FakeClock(),
        isLoggedIn: Boolean = true,
        config: SessionTimeoutCore.Config = SessionTimeoutCore.Config(),
    ): SessionTimeoutCore = SessionTimeout.forTest(
        isLoggedIn = isLoggedIn,
        nowMs = clock.provider,
        config = config,
    )

    // -------------------------------------------------------------------------
    // Config validation (line 402 — min/max enforced)
    // -------------------------------------------------------------------------

    @Test
    fun `default Config is valid`() {
        val config = SessionTimeoutCore.Config()
        assertEquals(15L * 60_000L, config.biometricAfterMs)
        assertEquals(4L * 60L * 60_000L, config.passwordAfterMs)
        assertEquals(30L * 24L * 60L * 60_000L, config.fullAuthAfterMs)
        assertEquals(60_000L, config.warningLeadMs)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `Config rejects biometricAfterMs below 1 minute`() {
        SessionTimeoutCore.Config(biometricAfterMs = 59_999L)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `Config rejects biometricAfterMs greater than fullAuthAfterMs`() {
        SessionTimeoutCore.Config(
            biometricAfterMs = 31L * 24L * 60L * 60_000L,
            fullAuthAfterMs = 30L * 24L * 60L * 60_000L,
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `Config rejects passwordAfterMs below biometricAfterMs`() {
        SessionTimeoutCore.Config(
            biometricAfterMs = 10L * 60_000L,
            passwordAfterMs = 9L * 60_000L,
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `Config rejects passwordAfterMs greater than fullAuthAfterMs`() {
        val full = 30L * 24L * 60L * 60_000L
        SessionTimeoutCore.Config(
            biometricAfterMs = 15L * 60_000L,
            passwordAfterMs = full + 1L,
            fullAuthAfterMs = full,
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `Config rejects fullAuthAfterMs above 30 days`() {
        SessionTimeoutCore.Config(fullAuthAfterMs = 31L * 24L * 60L * 60_000L)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `Config rejects warningLeadMs of zero`() {
        SessionTimeoutCore.Config(warningLeadMs = 0L)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `Config rejects warningLeadMs greater than biometricAfterMs`() {
        SessionTimeoutCore.Config(
            biometricAfterMs = 60_000L,
            warningLeadMs = 61_000L,
        )
    }

    @Test
    fun `Config with minimum biometricAfterMs and warningLeadMs equal to 1 minute is valid`() {
        val config = SessionTimeoutCore.Config(biometricAfterMs = 60_000L, warningLeadMs = 60_000L)
        assertEquals(60_000L, config.biometricAfterMs)
    }

    @Test
    fun `Config with fullAuthAfterMs exactly 30 days is valid`() {
        val config = SessionTimeoutCore.Config(fullAuthAfterMs = SessionTimeoutCore.MAX_FULL_AUTH_MS)
        assertEquals(SessionTimeoutCore.MAX_FULL_AUTH_MS, config.fullAuthAfterMs)
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    @Test
    fun `initial level is None`() {
        val st = make()
        assertEquals(SessionTimeoutCore.ReAuthLevel.None, st.state.value.level)
    }

    @Test
    fun `initial warningRemainingMs is null`() {
        val st = make()
        assertNull(st.state.value.warningRemainingMs)
    }

    @Test
    fun `initial lastActivityMs matches creation time`() {
        val clock = FakeClock(nowMs = 42_000L)
        val st = make(clock = clock)
        assertEquals(42_000L, st.state.value.lastActivityMs)
    }

    // -------------------------------------------------------------------------
    // onActivity resets the timer (line 397)
    // -------------------------------------------------------------------------

    @Test
    fun `onActivity resets lastActivityMs to current time`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        clock.nowMs = 5_000L
        st.onActivity()

        assertEquals(5_000L, st.state.value.lastActivityMs)
    }

    @Test
    fun `onActivity clears level back to None`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        // Advance past biometric threshold
        clock.nowMs = st.config.biometricAfterMs + 1L
        st.tick()
        assertEquals(SessionTimeoutCore.ReAuthLevel.Biometric, st.state.value.level)

        // User touches screen
        st.onActivity()
        assertEquals(SessionTimeoutCore.ReAuthLevel.None, st.state.value.level)
    }

    @Test
    fun `onActivity clears warning countdown`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        // Advance into warning window
        val warningStart = st.config.biometricAfterMs - st.config.warningLeadMs
        clock.nowMs = warningStart + 1L
        st.tick()
        assertNotNull(st.state.value.warningRemainingMs)

        st.onActivity()
        assertNull(st.state.value.warningRemainingMs)
    }

    // -------------------------------------------------------------------------
    // Warning window (lines 399-400)
    // -------------------------------------------------------------------------

    @Test
    fun `no warning when idle time is below warning start`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        val warningStart = st.config.biometricAfterMs - st.config.warningLeadMs
        clock.nowMs = warningStart - 1L
        st.tick()

        assertNull(st.state.value.warningRemainingMs)
    }

    @Test
    fun `warning starts exactly at biometricAfterMs minus warningLeadMs`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        val warningStart = st.config.biometricAfterMs - st.config.warningLeadMs
        clock.nowMs = warningStart
        st.tick()

        assertNotNull(st.state.value.warningRemainingMs)
        assertEquals(st.config.warningLeadMs, st.state.value.warningRemainingMs)
    }

    @Test
    fun `warningRemainingMs decreases as time advances`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        val warningStart = st.config.biometricAfterMs - st.config.warningLeadMs

        clock.nowMs = warningStart
        st.tick()
        val first = st.state.value.warningRemainingMs!!

        clock.nowMs = warningStart + 10_000L
        st.tick()
        val second = st.state.value.warningRemainingMs!!

        assertTrue("Warning countdown should decrease over time", second < first)
        assertEquals(first - 10_000L, second)
    }

    @Test
    fun `warning clears once biometric level fires`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        clock.nowMs = st.config.biometricAfterMs + 1L
        st.tick()

        assertEquals(SessionTimeoutCore.ReAuthLevel.Biometric, st.state.value.level)
        assertNull(
            "warningRemainingMs should be null once Biometric level fires",
            st.state.value.warningRemainingMs,
        )
    }

    // -------------------------------------------------------------------------
    // Level transitions (lines 394, 395, 396)
    // -------------------------------------------------------------------------

    @Test
    fun `level stays None before biometricAfterMs`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        clock.nowMs = st.config.biometricAfterMs - 1L
        st.tick()

        assertEquals(SessionTimeoutCore.ReAuthLevel.None, st.state.value.level)
    }

    @Test
    fun `level becomes Biometric at exactly biometricAfterMs`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        clock.nowMs = st.config.biometricAfterMs
        st.tick()

        assertEquals(SessionTimeoutCore.ReAuthLevel.Biometric, st.state.value.level)
    }

    @Test
    fun `level becomes Biometric just after biometricAfterMs`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        clock.nowMs = st.config.biometricAfterMs + 1L
        st.tick()

        assertEquals(SessionTimeoutCore.ReAuthLevel.Biometric, st.state.value.level)
    }

    @Test
    fun `level becomes Password at exactly passwordAfterMs`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        clock.nowMs = st.config.passwordAfterMs
        st.tick()

        assertEquals(SessionTimeoutCore.ReAuthLevel.Password, st.state.value.level)
    }

    @Test
    fun `level stays Password between password and full thresholds`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        clock.nowMs = (st.config.passwordAfterMs + st.config.fullAuthAfterMs) / 2
        st.tick()

        assertEquals(SessionTimeoutCore.ReAuthLevel.Password, st.state.value.level)
    }

    @Test
    fun `level becomes Full at exactly fullAuthAfterMs`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        clock.nowMs = st.config.fullAuthAfterMs
        st.tick()

        assertEquals(SessionTimeoutCore.ReAuthLevel.Full, st.state.value.level)
    }

    @Test
    fun `level remains Full beyond fullAuthAfterMs`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        clock.nowMs = st.config.fullAuthAfterMs + 1_000L
        st.tick()

        assertEquals(SessionTimeoutCore.ReAuthLevel.Full, st.state.value.level)
    }

    // -------------------------------------------------------------------------
    // requireReAuthNow (line 401)
    // -------------------------------------------------------------------------

    @Test
    fun `requireReAuthNow Biometric sets level immediately`() {
        val st = make()
        st.requireReAuthNow(SessionTimeoutCore.ReAuthLevel.Biometric)
        assertEquals(SessionTimeoutCore.ReAuthLevel.Biometric, st.state.value.level)
    }

    @Test
    fun `requireReAuthNow Full sets level immediately`() {
        val st = make()
        st.requireReAuthNow(SessionTimeoutCore.ReAuthLevel.Full)
        assertEquals(SessionTimeoutCore.ReAuthLevel.Full, st.state.value.level)
    }

    @Test
    fun `requireReAuthNow None is a no-op and does not downgrade active level`() {
        val st = make()
        st.requireReAuthNow(SessionTimeoutCore.ReAuthLevel.Biometric)
        st.requireReAuthNow(SessionTimeoutCore.ReAuthLevel.None)
        assertEquals(
            "requireReAuthNow(None) must not downgrade an active re-auth level",
            SessionTimeoutCore.ReAuthLevel.Biometric,
            st.state.value.level,
        )
    }

    @Test
    fun `requireReAuthNow clears warningRemainingMs`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        val warningStart = st.config.biometricAfterMs - st.config.warningLeadMs
        clock.nowMs = warningStart + 1L
        st.tick()
        assertNotNull(st.state.value.warningRemainingMs)

        st.requireReAuthNow(SessionTimeoutCore.ReAuthLevel.Password)

        assertNull(st.state.value.warningRemainingMs)
    }

    // -------------------------------------------------------------------------
    // clear()
    // -------------------------------------------------------------------------

    @Test
    fun `clear sets level back to None`() {
        val st = make()
        st.requireReAuthNow(SessionTimeoutCore.ReAuthLevel.Full)
        st.clear()
        assertEquals(SessionTimeoutCore.ReAuthLevel.None, st.state.value.level)
    }

    @Test
    fun `clear updates lastActivityMs to now`() {
        val clock = FakeClock(nowMs = 1_000L)
        val st = make(clock = clock)

        clock.nowMs = 9_000L
        st.clear()

        assertEquals(9_000L, st.state.value.lastActivityMs)
    }

    @Test
    fun `after clear timer restarts from new baseline`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        // Age past biometric threshold
        clock.nowMs = st.config.biometricAfterMs + 1L
        st.tick()
        assertEquals(SessionTimeoutCore.ReAuthLevel.Biometric, st.state.value.level)

        // User authenticates successfully
        st.clear()
        val baselineMs = st.state.value.lastActivityMs

        // Just under biometric threshold from clear time — should still be None
        clock.nowMs = baselineMs + st.config.biometricAfterMs - 1L
        st.tick()
        assertEquals(SessionTimeoutCore.ReAuthLevel.None, st.state.value.level)
    }

    // -------------------------------------------------------------------------
    // Sovereignty (line 403) — tick is no-op when not logged in
    // -------------------------------------------------------------------------

    @Test
    fun `tick is no-op when user is not logged in`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock, isLoggedIn = false)

        // Advance well past all thresholds
        clock.nowMs = st.config.fullAuthAfterMs + 1L
        st.tick()

        assertEquals(
            "tick must be no-op when isLoggedIn is false",
            SessionTimeoutCore.ReAuthLevel.None,
            st.state.value.level,
        )
    }

    // -------------------------------------------------------------------------
    // onAppBackground / onAppForeground (line 398 — non-user signals)
    // -------------------------------------------------------------------------

    @Test
    fun `onAppBackground does not reset lastActivityMs`() {
        val clock = FakeClock(nowMs = 100L)
        val st = make(clock = clock)
        st.onActivity() // sets lastActivityMs = 100

        clock.nowMs = 200L
        st.onAppBackground()

        assertEquals(
            "onAppBackground must not update lastActivityMs",
            100L,
            st.state.value.lastActivityMs,
        )
    }

    @Test
    fun `onAppForeground does not reset lastActivityMs`() {
        val clock = FakeClock(nowMs = 100L)
        val st = make(clock = clock)
        st.onActivity() // sets lastActivityMs = 100

        clock.nowMs = 500L
        st.onAppForeground()

        assertEquals(
            "onAppForeground must not update lastActivityMs",
            100L,
            st.state.value.lastActivityMs,
        )
    }

    @Test
    fun `inactivity accumulates through background pause`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)

        // User was active at t=0
        st.onActivity()

        // App goes to background and comes back after biometric threshold has passed
        clock.nowMs = st.config.biometricAfterMs + 1L
        st.onAppBackground()
        st.onAppForeground()
        st.tick()

        assertEquals(
            "Inactivity spanning background pause should trigger Biometric re-auth",
            SessionTimeoutCore.ReAuthLevel.Biometric,
            st.state.value.level,
        )
    }

    // -------------------------------------------------------------------------
    // State immutability
    // -------------------------------------------------------------------------

    @Test
    fun `tick emits new State objects on each change`() {
        val clock = FakeClock(nowMs = 0L)
        val st = make(clock = clock)
        val warningStart = st.config.biometricAfterMs - st.config.warningLeadMs

        clock.nowMs = warningStart
        st.tick()
        val state1 = st.state.value

        clock.nowMs = warningStart + 1_000L
        st.tick()
        val state2 = st.state.value

        assertTrue(
            "Each tick should produce a different State snapshot when content changes",
            state1 !== state2,
        )
    }
}
