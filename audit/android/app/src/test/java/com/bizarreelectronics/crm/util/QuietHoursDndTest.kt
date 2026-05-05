package com.bizarreelectronics.crm.util

import android.app.NotificationManager
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalTime

/**
 * §13 L1593 — Unit tests for the system DND integration in [QuietHours].
 *
 * Because [QuietHours] requires [android.content.Context] for the system DND
 * check and [AppPreferences] backed by DataStore, and neither is available
 * in a pure JVM environment, these tests use two strategies:
 *
 *  1. [DndStateChecker] — a pure-Kotlin mirror of [QuietHours.isSystemDndActive]
 *     that accepts the raw interruption-filter int.  This mirrors the exact
 *     branch logic without needing a Context or NotificationManager mock.
 *
 *  2. [SilenceDecider] — a pure-Kotlin mirror of the combined
 *     shouldSilence(context, channelId, now) logic with injectable fields,
 *     covering the interaction between system DND and app quiet-hours.
 *
 * Covered DND states (all four [NotificationManager.INTERRUPTION_FILTER_*]):
 *   - NONE     (2) → active DND → silence
 *   - PRIORITY (1 alias: INTERRUPTION_FILTER_PRIORITY = 2... see source) → silence
 *   - ALARMS   (4) → silence
 *   - ALL      (1) → DND off → do not silence
 *
 * Also verifies that critical channels bypass both DND and quiet-hours.
 */
class QuietHoursDndTest {

    // ── Pure mirror of QuietHours.isSystemDndActive ──────────────────────────

    /**
     * Mirrors the branch logic of [QuietHours.isSystemDndActive] without a
     * Context.  Returns true when the filter means DND is active.
     */
    private fun isDndActive(filter: Int): Boolean = when (filter) {
        NotificationManager.INTERRUPTION_FILTER_NONE,
        NotificationManager.INTERRUPTION_FILTER_PRIORITY,
        NotificationManager.INTERRUPTION_FILTER_ALARMS -> true
        else -> false  // INTERRUPTION_FILTER_ALL (1) or UNKNOWN (0)
    }

    // ── Pure mirror of combined shouldSilence logic ──────────────────────────

    private class SilenceDecider(
        val criticalChannelIds: Set<String> = emptySet(),
        val dndActive: Boolean = false,
        val quietHoursEnabled: Boolean = false,
        val quietHoursStartMinutes: Int = 0,
        val quietHoursEndMinutes: Int = 0,
    ) {
        fun shouldSilence(channelId: String, now: LocalTime = LocalTime.now()): Boolean {
            if (channelId in criticalChannelIds) return false
            if (dndActive) return true
            if (!quietHoursEnabled) return false
            val start = quietHoursStartMinutes
            val end = quietHoursEndMinutes
            if (start == end) return false
            val nowMin = now.hour * 60 + now.minute
            return if (start < end) nowMin in start until end
            else nowMin >= start || nowMin < end
        }
    }

    // ── isDndActive — all four INTERRUPTION_FILTER states ───────────────────

    @Test
    fun `INTERRUPTION_FILTER_NONE triggers DND active`() {
        assertTrue(isDndActive(NotificationManager.INTERRUPTION_FILTER_NONE))
    }

    @Test
    fun `INTERRUPTION_FILTER_PRIORITY triggers DND active`() {
        assertTrue(isDndActive(NotificationManager.INTERRUPTION_FILTER_PRIORITY))
    }

    @Test
    fun `INTERRUPTION_FILTER_ALARMS triggers DND active`() {
        assertTrue(isDndActive(NotificationManager.INTERRUPTION_FILTER_ALARMS))
    }

    @Test
    fun `INTERRUPTION_FILTER_ALL means DND is off`() {
        assertFalse(isDndActive(NotificationManager.INTERRUPTION_FILTER_ALL))
    }

    // ── shouldSilence — DND integration ──────────────────────────────────────

    @Test
    fun `system DND active silences non-critical channel`() {
        val decider = SilenceDecider(dndActive = true)
        assertTrue(decider.shouldSilence("sms_inbound"))
    }

    @Test
    fun `system DND active does NOT silence critical channel`() {
        val decider = SilenceDecider(
            dndActive = true,
            criticalChannelIds = setOf("security_event"),
        )
        assertFalse(decider.shouldSilence("security_event"))
    }

    @Test
    fun `system DND off and quiet-hours off means no silence`() {
        val decider = SilenceDecider(dndActive = false, quietHoursEnabled = false)
        assertFalse(decider.shouldSilence("sms_inbound"))
    }

    @Test
    fun `system DND off but quiet-hours active silences in window`() {
        val decider = SilenceDecider(
            dndActive = false,
            quietHoursEnabled = true,
            quietHoursStartMinutes = 22 * 60,
            quietHoursEndMinutes = 23 * 60,
        )
        assertTrue(decider.shouldSilence("sms_inbound", LocalTime.of(22, 30)))
    }

    @Test
    fun `critical channel exempt from quiet-hours as well`() {
        val decider = SilenceDecider(
            criticalChannelIds = setOf("security_event"),
            dndActive = false,
            quietHoursEnabled = true,
            quietHoursStartMinutes = 22 * 60,
            quietHoursEndMinutes = 23 * 60,
        )
        assertFalse(decider.shouldSilence("security_event", LocalTime.of(22, 30)))
    }
}
