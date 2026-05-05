package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.Instant

/**
 * Unit tests for [ClockDrift].
 *
 * All tests use controlled server timestamps derived from a known base
 * (System.currentTimeMillis()) so they are independent of wall-clock
 * skew on the CI host.
 */
class ClockDriftTest {

    private lateinit var clockDrift: ClockDrift

    @Before
    fun setUp() {
        clockDrift = ClockDrift()
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    @Test
    fun `initial state has zero drift, no server time, and no warning`() {
        val state = clockDrift.state.value
        assertEquals(0L, state.driftMs)
        assertFalse("serverTimeAvailable should be false before first header", state.serverTimeAvailable)
        assertFalse("warnThresholdCrossed should be false at init", state.warnThresholdCrossed)
    }

    @Test
    fun `isSafeFor2FA returns true when no server time is available`() {
        // Optimistic default — don't block 2FA before we have evidence of a problem.
        assertTrue("isSafeFor2FA should default to true when serverTimeAvailable is false",
            clockDrift.isSafeFor2FA())
    }

    // -------------------------------------------------------------------------
    // Zero / negligible drift
    // -------------------------------------------------------------------------

    @Test
    fun `zero drift does not trigger warning`() {
        clockDrift.recordServerDate(System.currentTimeMillis())

        val state = clockDrift.state.value
        assertTrue("serverTimeAvailable should be true after recordServerDate", state.serverTimeAvailable)
        assertFalse("warnThresholdCrossed should be false for zero drift", state.warnThresholdCrossed)
    }

    @Test
    fun `isSafeFor2FA true at exactly zero drift`() {
        clockDrift.recordServerDate(System.currentTimeMillis())
        assertTrue(clockDrift.isSafeFor2FA())
    }

    @Test
    fun `drift below 10 seconds is safe for 2FA`() {
        val tenSecondsAhead = System.currentTimeMillis() + 10_000L
        clockDrift.recordServerDate(tenSecondsAhead)

        assertTrue("10 second drift should be safe for 2FA", clockDrift.isSafeFor2FA())
        assertFalse("10 second drift should not trigger warning", clockDrift.state.value.warnThresholdCrossed)
    }

    // -------------------------------------------------------------------------
    // Warning threshold (> 2 minutes)
    // -------------------------------------------------------------------------

    @Test
    fun `drift of exactly 2 minutes does not trigger warning`() {
        // Threshold is STRICTLY GREATER THAN 2 min, so exactly 2 min is safe.
        val twoMinutesAhead = System.currentTimeMillis() + ClockDrift.WARN_DRIFT_MS
        clockDrift.recordServerDate(twoMinutesAhead)

        assertFalse("Drift exactly at threshold should NOT trigger warning",
            clockDrift.state.value.warnThresholdCrossed)
    }

    @Test
    fun `drift greater than 2 minutes triggers warning`() {
        val threeMinutesAhead = System.currentTimeMillis() + (3 * 60 * 1000L)
        clockDrift.recordServerDate(threeMinutesAhead)

        val state = clockDrift.state.value
        assertTrue("3-minute drift should trigger warning", state.warnThresholdCrossed)
        assertTrue("serverTimeAvailable should be true", state.serverTimeAvailable)
        assertTrue("driftMs should be positive (server ahead)", state.driftMs > 0)
    }

    @Test
    fun `negative drift of 3 minutes also triggers warning`() {
        // Device clock is ahead of server by 3 minutes.
        val threeMinutesBehind = System.currentTimeMillis() - (3 * 60 * 1000L)
        clockDrift.recordServerDate(threeMinutesBehind)

        assertTrue("Negative 3-minute drift should also trigger warning",
            clockDrift.state.value.warnThresholdCrossed)
    }

    // -------------------------------------------------------------------------
    // TOTP gate (isSafeFor2FA)
    // -------------------------------------------------------------------------

    @Test
    fun `isSafeFor2FA false at 1 minute drift`() {
        val oneMinuteAhead = System.currentTimeMillis() + (60 * 1000L)
        clockDrift.recordServerDate(oneMinuteAhead)

        assertFalse("1-minute drift should fail isSafeFor2FA", clockDrift.isSafeFor2FA())
    }

    @Test
    fun `isSafeFor2FA true at 10 seconds drift`() {
        val tenSecondsAhead = System.currentTimeMillis() + 10_000L
        clockDrift.recordServerDate(tenSecondsAhead)

        assertTrue("10-second drift should pass isSafeFor2FA", clockDrift.isSafeFor2FA())
    }

    @Test
    fun `isSafeFor2FA false at exactly 30 second threshold`() {
        // Threshold is STRICTLY LESS THAN TOTP_DRIFT_MS, so 30s is unsafe.
        val thirtySecondsAhead = System.currentTimeMillis() + ClockDrift.TOTP_DRIFT_MS
        clockDrift.recordServerDate(thirtySecondsAhead)

        assertFalse("Drift exactly at TOTP threshold should be unsafe for 2FA",
            clockDrift.isSafeFor2FA())
    }

    @Test
    fun `isSafeFor2FA false for negative 1 minute drift`() {
        val oneMinuteBehind = System.currentTimeMillis() - (60 * 1000L)
        clockDrift.recordServerDate(oneMinuteBehind)

        assertFalse("Negative 1-minute drift should also fail isSafeFor2FA", clockDrift.isSafeFor2FA())
    }

    // -------------------------------------------------------------------------
    // toAuditTimestamp
    // -------------------------------------------------------------------------

    @Test
    fun `toAuditTimestamp without server time returns local epoch unchanged`() {
        val localMs = System.currentTimeMillis()
        val ts = clockDrift.toAuditTimestamp(localMs)

        assertEquals("Without server time, drift is 0 and timestamp equals localMs",
            localMs, ts.toEpochMilli())
    }

    @Test
    fun `toAuditTimestamp corrects for positive drift`() {
        val drift = 5_000L // server is 5 seconds ahead of device
        val localMs = System.currentTimeMillis()
        clockDrift.recordServerDate(localMs + drift)

        // Small race window: re-capture localMs *after* recordServerDate so the
        // drift measurement and our expected calculation share the same device now.
        val eventMs = System.currentTimeMillis()
        val ts = clockDrift.toAuditTimestamp(eventMs)

        val expectedDrift = clockDrift.state.value.driftMs
        val expected = Instant.ofEpochMilli(eventMs + expectedDrift)
        assertEquals("toAuditTimestamp should apply recorded drift", expected, ts)
    }

    @Test
    fun `toAuditTimestamp corrects for negative drift`() {
        val drift = -3_000L // device is 3 seconds ahead of server
        val localMs = System.currentTimeMillis()
        clockDrift.recordServerDate(localMs + drift)

        val eventMs = System.currentTimeMillis()
        val ts = clockDrift.toAuditTimestamp(eventMs)

        val expectedDrift = clockDrift.state.value.driftMs
        val expected = Instant.ofEpochMilli(eventMs + expectedDrift)
        assertEquals("toAuditTimestamp should apply negative drift", expected, ts)
    }

    @Test
    fun `toAuditTimestamp returns Instant (not null)`() {
        val ts = clockDrift.toAuditTimestamp(System.currentTimeMillis())
        assertNotNull(ts)
    }

    // -------------------------------------------------------------------------
    // recordPendingOp / PendingOpTimestamps
    // -------------------------------------------------------------------------

    @Test
    fun `recordPendingOp stores deviceMs and null offlineSinceMs`() {
        val now = System.currentTimeMillis()
        val op = clockDrift.recordPendingOp(deviceMs = now, offlineSinceMs = null)

        assertEquals(now, op.deviceMs)
        assertEquals(null, op.offlineSinceMs)
    }

    @Test
    fun `recordPendingOp stores both timestamps when offline since is provided`() {
        val now = System.currentTimeMillis()
        val wentOffline = now - 60_000L
        val op = clockDrift.recordPendingOp(deviceMs = now, offlineSinceMs = wentOffline)

        assertEquals(now, op.deviceMs)
        assertEquals(wentOffline, op.offlineSinceMs)
    }

    @Test
    fun `recordPendingOp is pure — does not alter drift state`() {
        clockDrift.recordServerDate(System.currentTimeMillis() + 5_000L)
        val stateBefore = clockDrift.state.value

        clockDrift.recordPendingOp(deviceMs = System.currentTimeMillis(), offlineSinceMs = null)

        assertEquals("recordPendingOp must not mutate drift state", stateBefore, clockDrift.state.value)
    }

    // -------------------------------------------------------------------------
    // State immutability — copy() semantics
    // -------------------------------------------------------------------------

    @Test
    fun `multiple recordServerDate calls each produce independent State snapshots`() {
        val first = System.currentTimeMillis() + 1_000L
        clockDrift.recordServerDate(first)
        val stateAfterFirst = clockDrift.state.value

        val second = System.currentTimeMillis() + 10_000L
        clockDrift.recordServerDate(second)
        val stateAfterSecond = clockDrift.state.value

        assertTrue("States should differ after two different server dates",
            stateAfterFirst !== stateAfterSecond)
    }

    // -------------------------------------------------------------------------
    // Companion object constants
    // -------------------------------------------------------------------------

    @Test
    fun `WARN_DRIFT_MS is 2 minutes`() {
        assertEquals(2 * 60 * 1000L, ClockDrift.WARN_DRIFT_MS)
    }

    @Test
    fun `TOTP_DRIFT_MS is 30 seconds`() {
        assertEquals(30 * 1000L, ClockDrift.TOTP_DRIFT_MS)
    }
}
