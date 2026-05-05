package com.bizarreelectronics.crm.ui.components

import com.bizarreelectronics.crm.data.local.draft.DraftStore
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pure-JVM unit tests for the helper functions in [DraftRecoveryPrompt]
 * (ActionPlan §1 L261).
 *
 * No Compose runtime or Android instrumentation is needed — [formatDraftAge]
 * and [draftTypeLabel] are both `internal` top-level functions that take only
 * primitives and enums.
 *
 * Coverage: ≥ 10 test cases covering all branches in [formatDraftAge] plus
 * all three [DraftStore.DraftType] labels.
 */
class DraftRecoveryPromptTest {

    // -----------------------------------------------------------------------
    // formatDraftAge — "just now" branch (< 1 minute elapsed)
    // -----------------------------------------------------------------------

    @Test
    fun `formatDraftAge zero elapsed returns just now`() {
        val now = 1_000_000L
        assertEquals("just now", formatDraftAge(savedAtMs = now, nowMs = now))
    }

    @Test
    fun `formatDraftAge 30 seconds elapsed returns just now`() {
        val now = 1_000_000L
        assertEquals("just now", formatDraftAge(savedAtMs = now - 30_000L, nowMs = now))
    }

    @Test
    fun `formatDraftAge 59999ms elapsed returns just now`() {
        val now = 1_000_000L
        assertEquals("just now", formatDraftAge(savedAtMs = now - 59_999L, nowMs = now))
    }

    // -----------------------------------------------------------------------
    // formatDraftAge — minutes branch (1 min .. < 1 hr)
    // -----------------------------------------------------------------------

    @Test
    fun `formatDraftAge exactly 1 minute elapsed returns Saved 1m ago`() {
        val now = 10_000_000L
        assertEquals("Saved 1m ago", formatDraftAge(savedAtMs = now - 60_000L, nowMs = now))
    }

    @Test
    fun `formatDraftAge 45 minutes elapsed returns Saved 45m ago`() {
        val now = 10_000_000L
        assertEquals("Saved 45m ago", formatDraftAge(savedAtMs = now - 45 * 60_000L, nowMs = now))
    }

    @Test
    fun `formatDraftAge 59 minutes elapsed returns Saved 59m ago`() {
        val now = 10_000_000L
        assertEquals("Saved 59m ago", formatDraftAge(savedAtMs = now - 59 * 60_000L, nowMs = now))
    }

    // -----------------------------------------------------------------------
    // formatDraftAge — hours branch (1 hr .. < 1 day)
    // -----------------------------------------------------------------------

    @Test
    fun `formatDraftAge exactly 1 hour elapsed returns Saved 1h ago`() {
        val now = 100_000_000L
        assertEquals("Saved 1h ago", formatDraftAge(savedAtMs = now - 3_600_000L, nowMs = now))
    }

    @Test
    fun `formatDraftAge 3 hours elapsed returns Saved 3h ago`() {
        val now = 100_000_000L
        assertEquals("Saved 3h ago", formatDraftAge(savedAtMs = now - 3 * 3_600_000L, nowMs = now))
    }

    @Test
    fun `formatDraftAge 23 hours elapsed returns Saved 23h ago`() {
        val now = 100_000_000L
        assertEquals("Saved 23h ago", formatDraftAge(savedAtMs = now - 23 * 3_600_000L, nowMs = now))
    }

    // -----------------------------------------------------------------------
    // formatDraftAge — days branch (1 day .. 30 days)
    // -----------------------------------------------------------------------

    @Test
    fun `formatDraftAge exactly 1 day elapsed returns Saved 1d ago`() {
        val now = 200_000_000L
        assertEquals("Saved 1d ago", formatDraftAge(savedAtMs = now - 86_400_000L, nowMs = now))
    }

    @Test
    fun `formatDraftAge 7 days elapsed returns Saved 7d ago`() {
        val now = 200_000_000L
        assertEquals("Saved 7d ago", formatDraftAge(savedAtMs = now - 7 * 86_400_000L, nowMs = now))
    }

    @Test
    fun `formatDraftAge exactly 30 days elapsed returns Saved 30d ago`() {
        val now = 200_000_000L
        assertEquals("Saved 30d ago", formatDraftAge(savedAtMs = now - 30 * 86_400_000L, nowMs = now))
    }

    // -----------------------------------------------------------------------
    // formatDraftAge — stale branch (> 30 days)
    // -----------------------------------------------------------------------

    @Test
    fun `formatDraftAge 31 days elapsed returns stale message`() {
        val now = 300_000_000L
        assertEquals(
            "Saved >30 days ago (stale)",
            formatDraftAge(savedAtMs = now - 31 * 86_400_000L, nowMs = now),
        )
    }

    @Test
    fun `formatDraftAge 365 days elapsed returns stale message`() {
        val now = 300_000_000L
        assertEquals(
            "Saved >30 days ago (stale)",
            formatDraftAge(savedAtMs = now - 365 * 86_400_000L, nowMs = now),
        )
    }

    // -----------------------------------------------------------------------
    // formatDraftAge — clock-skew guard (savedAtMs > nowMs)
    // -----------------------------------------------------------------------

    @Test
    fun `formatDraftAge future savedAt is clamped to just now`() {
        val now = 1_000_000L
        // savedAtMs is 5 seconds in the future — elapsed clamps to 0
        assertEquals("just now", formatDraftAge(savedAtMs = now + 5_000L, nowMs = now))
    }

    @Test
    fun `formatDraftAge savedAt 1 hour in future is clamped to just now`() {
        val now = 1_000_000L
        assertEquals("just now", formatDraftAge(savedAtMs = now + 3_600_000L, nowMs = now))
    }

    // -----------------------------------------------------------------------
    // draftTypeLabel — all three enum variants
    // -----------------------------------------------------------------------

    @Test
    fun `draftTypeLabel TICKET returns ticket`() {
        assertEquals("ticket", draftTypeLabel(DraftStore.DraftType.TICKET))
    }

    @Test
    fun `draftTypeLabel CUSTOMER returns customer`() {
        assertEquals("customer", draftTypeLabel(DraftStore.DraftType.CUSTOMER))
    }

    @Test
    fun `draftTypeLabel SMS returns SMS draft`() {
        assertEquals("SMS draft", draftTypeLabel(DraftStore.DraftType.SMS))
    }
}
