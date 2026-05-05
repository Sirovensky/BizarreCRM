package com.bizarreelectronics.crm.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * JVM unit tests for [driftToText], the pure formatter extracted from
 * [ClockDriftBanner] (ActionPlan §1 L251).
 *
 * These tests do not require a Compose or Android environment — they only
 * exercise the pure `internal fun driftToText(driftMs: Long): String` helper.
 *
 * Sign convention under test:
 *   driftMs = serverEpochMs − deviceMs
 *   - positive → server ahead → device clock is slow   → "slow"
 *   - negative → device ahead → device clock is fast   → "fast"
 */
class ClockDriftBannerTest {

    // -------------------------------------------------------------------------
    // Minutes — positive drift (device slow)
    // -------------------------------------------------------------------------

    @Test
    fun `positive drift of exactly 2 minutes shows 2 minutes slow`() {
        assertEquals("2 minutes slow", driftToText(2 * 60_000L))
    }

    @Test
    fun `positive drift of 1 minute shows singular minute slow`() {
        assertEquals("1 minute slow", driftToText(60_000L))
    }

    @Test
    fun `positive drift of 3 minutes 30 seconds shows 3 minutes slow (truncated)`() {
        // 3.5 minutes = 210_000 ms. Integer division truncates to 3.
        assertEquals("3 minutes slow", driftToText(210_000L))
    }

    @Test
    fun `positive drift of 10 minutes shows 10 minutes slow`() {
        assertEquals("10 minutes slow", driftToText(10 * 60_000L))
    }

    // -------------------------------------------------------------------------
    // Minutes — negative drift (device fast)
    // -------------------------------------------------------------------------

    @Test
    fun `negative drift of 2 minutes shows 2 minutes fast`() {
        assertEquals("2 minutes fast", driftToText(-2 * 60_000L))
    }

    @Test
    fun `negative drift of 1 minute shows singular minute fast`() {
        assertEquals("1 minute fast", driftToText(-60_000L))
    }

    @Test
    fun `negative drift of 5 minutes shows 5 minutes fast`() {
        assertEquals("5 minutes fast", driftToText(-5 * 60_000L))
    }

    // -------------------------------------------------------------------------
    // Seconds — positive drift (device slow, sub-minute)
    // -------------------------------------------------------------------------

    @Test
    fun `positive drift of 45 seconds shows 45 seconds slow`() {
        assertEquals("45 seconds slow", driftToText(45_000L))
    }

    @Test
    fun `positive drift of 1 second shows singular second slow`() {
        assertEquals("1 second slow", driftToText(1_000L))
    }

    @Test
    fun `positive drift of 30 seconds shows 30 seconds slow`() {
        assertEquals("30 seconds slow", driftToText(30_000L))
    }

    @Test
    fun `positive drift of 59 seconds shows 59 seconds slow`() {
        // 59_999 ms is still sub-minute
        assertEquals("59 seconds slow", driftToText(59_000L))
    }

    // -------------------------------------------------------------------------
    // Seconds — negative drift (device fast, sub-minute)
    // -------------------------------------------------------------------------

    @Test
    fun `negative drift of 29 seconds shows 29 seconds fast`() {
        assertEquals("29 seconds fast", driftToText(-29_000L))
    }

    @Test
    fun `negative drift of 1 second shows singular second fast`() {
        assertEquals("1 second fast", driftToText(-1_000L))
    }

    // -------------------------------------------------------------------------
    // Boundary at exactly 60_000ms
    // -------------------------------------------------------------------------

    @Test
    fun `drift of exactly 60 seconds transitions to minutes display`() {
        // 60_000ms = exactly 1 minute — should show "1 minute slow", not "60 seconds slow"
        assertEquals("1 minute slow", driftToText(60_000L))
    }

    @Test
    fun `drift of 59_999ms stays in seconds display`() {
        // Just below the boundary
        assertEquals("59 seconds slow", driftToText(59_999L))
    }

    // -------------------------------------------------------------------------
    // Zero drift (edge case — not normally shown since warnThresholdCrossed is false)
    // -------------------------------------------------------------------------

    @Test
    fun `zero drift shows 0 seconds slow`() {
        assertEquals("0 seconds slow", driftToText(0L))
    }
}
