package com.bizarreelectronics.crm.util

import com.bizarreelectronics.crm.data.remote.api.SlaDefinitionDto
import com.bizarreelectronics.crm.util.SlaCalculator.SlaTier
import com.bizarreelectronics.crm.util.SlaCalculator.StatusHistoryEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [SlaCalculator] — §4.19 L825-L835.
 *
 * All times are in epoch-milliseconds (Long).
 */
class SlaCalculatorTest {

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private val MIN = 60_000L   // 1 minute in ms
    private val HR  = 60 * MIN  // 1 hour  in ms

    private fun sla(repairMinutes: Int) = SlaDefinitionDto(
        id = 1L,
        serviceType = "screen_repair",
        diagnoseMinutes = 30,
        repairMinutes = repairMinutes,
        smsMinutes = 5,
    )

    private fun slaNoRepair() = SlaDefinitionDto(
        id = 2L,
        serviceType = "custom",
        diagnoseMinutes = null,
        repairMinutes = null,
        smsMinutes = null,
    )

    // ─── remainingMs — no pauses ──────────────────────────────────────────────

    @Test
    fun `no pauses - half SLA consumed`() {
        // Budget: 120 min = 7_200_000 ms.
        // Elapsed: 60 min. Expected remaining: 60 min.
        val created = 0L
        val now     = 60 * MIN
        val rem = SlaCalculator.remainingMs(created, now, sla(120), emptyList())
        assertEquals(60 * MIN, rem)
    }

    @Test
    fun `no pauses - SLA fully consumed returns negative`() {
        val created = 0L
        val now     = 130 * MIN  // 10 min past 120-min budget
        val rem = SlaCalculator.remainingMs(created, now, sla(120), emptyList())
        assertEquals(-(10 * MIN), rem)
    }

    @Test
    fun `no SLA defined returns MAX_VALUE`() {
        val rem = SlaCalculator.remainingMs(0L, HR, slaNoRepair(), emptyList())
        assertEquals(Long.MAX_VALUE, rem)
    }

    // ─── Pause / resume math ─────────────────────────────────────────────────

    @Test
    fun `single closed pause window deducted correctly`() {
        // Ticket created at t=0. At t=20 min → awaiting_parts. At t=50 min → back to repair.
        // Pause window = 30 min. Elapsed counting toward SLA = (now - created - paused).
        // now = 90 min → elapsed_active = 90 - 30 = 60 min. Budget 120 min → rem = 60 min.
        val history = listOf(
            StatusHistoryEntry("In Repair",        enteredAtMs = 0L),
            StatusHistoryEntry("awaiting_parts",   enteredAtMs = 20 * MIN),
            StatusHistoryEntry("In Repair",        enteredAtMs = 50 * MIN),
        )
        val rem = SlaCalculator.remainingMs(0L, 90 * MIN, sla(120), history)
        assertEquals(60 * MIN, rem)
    }

    @Test
    fun `open pause window capped at now`() {
        // Ticket at t=0. Went awaiting_customer at t=10. Still awaiting at now=50.
        // Paused = 40 min. Active = 50 - 40 = 10 min. Budget 60 → rem = 50 min.
        val history = listOf(
            StatusHistoryEntry("In Repair",          enteredAtMs = 0L),
            StatusHistoryEntry("awaiting customer",   enteredAtMs = 10 * MIN),
        )
        val rem = SlaCalculator.remainingMs(0L, 50 * MIN, sla(60), history)
        assertEquals(50 * MIN, rem)
    }

    @Test
    fun `multiple pause windows accumulated correctly`() {
        // Two pause windows: 10 min + 5 min = 15 min total paused.
        // Elapsed active at now=80 min = 80 - 15 = 65 min. Budget=120 → rem=55 min.
        val history = listOf(
            StatusHistoryEntry("In Repair",         enteredAtMs = 0L),
            StatusHistoryEntry("awaiting_parts",    enteredAtMs = 10 * MIN),
            StatusHistoryEntry("In Repair",         enteredAtMs = 20 * MIN),  // +10 min pause
            StatusHistoryEntry("awaiting customer", enteredAtMs = 50 * MIN),
            StatusHistoryEntry("In Repair",         enteredAtMs = 55 * MIN),  // +5 min pause
        )
        val rem = SlaCalculator.remainingMs(0L, 80 * MIN, sla(120), history)
        assertEquals(55 * MIN, rem)
    }

    @Test
    fun `paused entire duration means no SLA consumed`() {
        // Ticket awaiting_parts from creation to now. Budget 60 min.
        val history = listOf(
            StatusHistoryEntry("awaiting_parts", enteredAtMs = 0L),
        )
        val rem = SlaCalculator.remainingMs(0L, 59 * MIN, sla(60), history)
        assertEquals(60 * MIN, rem)  // full budget remaining
    }

    // ─── Amber / red thresholds ───────────────────────────────────────────────

    @Test
    fun `tier is Green when more than 25 pct remaining`() {
        assertEquals(SlaTier.Green, SlaCalculator.tier(100))
        assertEquals(SlaTier.Green, SlaCalculator.tier(26))
    }

    @Test
    fun `tier is Amber at exactly 25 pct remaining`() {
        assertEquals(SlaTier.Amber, SlaCalculator.tier(25))
    }

    @Test
    fun `tier is Amber between 1 and 25 pct`() {
        assertEquals(SlaTier.Amber, SlaCalculator.tier(1))
        assertEquals(SlaTier.Amber, SlaCalculator.tier(10))
    }

    @Test
    fun `tier is Red at 0 pct`() {
        assertEquals(SlaTier.Red, SlaCalculator.tier(0))
    }

    @Test
    fun `tier is Red when negative pct (breached)`() {
        assertEquals(SlaTier.Red, SlaCalculator.tier(-5))
    }

    @Test
    fun `remainingPct 75 pct consumed gives amber boundary`() {
        // Budget 120 min, elapsed 90 min → 30 min remaining = 25 %.
        val pct = SlaCalculator.remainingPct(0L, 90 * MIN, sla(120), emptyList())
        assertEquals(25, pct)
        assertEquals(SlaTier.Amber, SlaCalculator.tier(pct))
    }

    // ─── Breach projection ────────────────────────────────────────────────────

    @Test
    fun `projectedBreachMs returns nowMs plus remainingMs when not yet breached`() {
        // Budget 120 min, elapsed 60 min → 60 min remaining. Breach at now + 60 min.
        val now = 60 * MIN
        val projected = SlaCalculator.projectedBreachMs(0L, now, sla(120), emptyList())
        assertEquals(now + 60 * MIN, projected)
    }

    @Test
    fun `projectedBreachMs returns null when already breached`() {
        val projected = SlaCalculator.projectedBreachMs(0L, 130 * MIN, sla(120), emptyList())
        assertNull(projected)
    }

    @Test
    fun `projectedBreachMs returns null when no SLA defined`() {
        val projected = SlaCalculator.projectedBreachMs(0L, HR, slaNoRepair(), emptyList())
        assertNull(projected)
    }

    // ─── Edge cases ───────────────────────────────────────────────────────────

    @Test
    fun `empty status history treated as no pauses`() {
        val paused = SlaCalculator.computePausedMs(emptyList(), 60 * MIN)
        assertEquals(0L, paused)
    }

    @Test
    fun `status name matching is case-insensitive`() {
        val history = listOf(
            StatusHistoryEntry("Awaiting_Customer", enteredAtMs = 0L),
            StatusHistoryEntry("In Repair",         enteredAtMs = 30 * MIN),
        )
        val paused = SlaCalculator.computePausedMs(history, 60 * MIN)
        assertEquals(30 * MIN, paused)
    }

    @Test
    fun `status name with extra spaces still matches`() {
        val history = listOf(
            StatusHistoryEntry("  Awaiting Parts  ", enteredAtMs = 0L),
            StatusHistoryEntry("Ready",               enteredAtMs = 15 * MIN),
        )
        val paused = SlaCalculator.computePausedMs(history, 30 * MIN)
        assertEquals(15 * MIN, paused)
    }

    @Test
    fun `null status name not treated as pause`() {
        val history = listOf(
            StatusHistoryEntry(null, enteredAtMs = 0L),
            StatusHistoryEntry("In Repair", enteredAtMs = 30 * MIN),
        )
        val paused = SlaCalculator.computePausedMs(history, 60 * MIN)
        assertEquals(0L, paused)
    }

    @Test
    fun `remainingPct 100 when no SLA defined`() {
        val pct = SlaCalculator.remainingPct(0L, HR, slaNoRepair(), emptyList())
        assertEquals(100, pct)
    }

    @Test
    fun `remainingMs never returns positive when elapsed exceeds budget plus pauses`() {
        // elapsed_active = 200 min, budget = 60 min → rem = -140 min
        val history = listOf(
            StatusHistoryEntry("In Repair",       enteredAtMs = 0L),
            StatusHistoryEntry("awaiting_parts",  enteredAtMs = 50 * MIN),
            StatusHistoryEntry("In Repair",       enteredAtMs = 110 * MIN), // 60 min paused
        )
        // total elapsed = 200 min, paused = 60 min, active = 140 min, budget = 60 → rem = -80 min
        val rem = SlaCalculator.remainingMs(0L, 200 * MIN, sla(60), history)
        assertTrue("expected negative remaining when breached", rem < 0)
        assertEquals(-(80 * MIN), rem)
    }
}
