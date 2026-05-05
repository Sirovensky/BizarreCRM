package com.bizarreelectronics.crm.util

import com.bizarreelectronics.crm.data.remote.api.SlaDefinitionDto

/**
 * §4.19 L825-L835 — Pure Kotlin SLA calculator (no Android dependencies).
 *
 * Computes remaining SLA time for a ticket, accounting for paused periods
 * (statuses that don't count against the clock).
 *
 * ### Pause statuses
 * The SLA clock is paused while a ticket is in any of the following status
 * categories (matched case-insensitively against [StatusHistoryEntry.statusName]):
 * - "awaiting_customer" / "awaiting customer"
 * - "awaiting_parts"   / "awaiting parts"
 *
 * ### Amber / red thresholds
 * - Green  → remaining > 25 % of total SLA budget
 * - Amber  → remaining ≤ 25 % and > 0 %  (i.e. used ≥ 75 % of budget)
 * - Red    → remaining ≤ 0 % (deadline passed / breached)
 *
 * The choice of 25 % as the amber boundary means amber starts at 75 % consumption,
 * matching the spec ("amber at 75 % / red at 100 %").
 *
 * All inputs and outputs use epoch-milliseconds (Long) to keep the class
 * testable without date/time library dependencies.
 */
object SlaCalculator {

    /** Status names (lowercase, trimmed) that pause the SLA clock. */
    private val PAUSE_STATUS_PATTERNS = listOf(
        "awaiting_customer",
        "awaiting customer",
        "awaiting_parts",
        "awaiting parts",
    )

    /**
     * A point-in-time entry in a ticket's status history.
     *
     * @param statusName  Human-readable status name (may be null for the initial entry).
     * @param enteredAtMs Epoch ms when the ticket entered this status.
     */
    data class StatusHistoryEntry(
        val statusName: String?,
        val enteredAtMs: Long,
    )

    /**
     * SLA tier based on remaining time.
     *
     * - [Green]  → > 25 % remaining
     * - [Amber]  → ≤ 25 % remaining, > 0 %
     * - [Red]    → ≤ 0 % remaining (breached)
     */
    enum class SlaTier { Green, Amber, Red }

    /**
     * Compute remaining SLA milliseconds for a ticket.
     *
     * The total SLA budget is derived from [sla].repairMinutes (primary).
     * If repairMinutes is null the function returns [Long.MAX_VALUE] (no SLA defined).
     *
     * @param createdAtMs       Epoch ms when the ticket was created.
     * @param nowMs             Current epoch ms (injectable for testability).
     * @param sla               SLA definition for the ticket's service type.
     * @param statusHistory     Ordered list of status history entries, oldest first.
     *                          May be empty — in that case no pauses are applied.
     * @return Remaining milliseconds. Negative means the deadline is in the past.
     */
    fun remainingMs(
        createdAtMs: Long,
        nowMs: Long,
        sla: SlaDefinitionDto,
        statusHistory: List<StatusHistoryEntry>,
    ): Long {
        val budgetMs = sla.repairMinutes?.let { it.toLong() * 60_000L }
            ?: return Long.MAX_VALUE

        val pausedMs = computePausedMs(statusHistory, nowMs)
        val elapsed = (nowMs - createdAtMs - pausedMs).coerceAtLeast(0L)
        return budgetMs - elapsed
    }

    /**
     * Compute total paused duration in milliseconds.
     *
     * Walks [statusHistory] to find contiguous "pause window" intervals where
     * the ticket was in a pause-eligible status. An open pause window (the last
     * entry in history still has a pause status) is capped at [nowMs].
     */
    fun computePausedMs(
        statusHistory: List<StatusHistoryEntry>,
        nowMs: Long,
    ): Long {
        if (statusHistory.isEmpty()) return 0L

        var paused = 0L
        var pauseWindowStartMs: Long? = null

        for (entry in statusHistory) {
            val isPause = isPauseStatus(entry.statusName)
            if (isPause && pauseWindowStartMs == null) {
                pauseWindowStartMs = entry.enteredAtMs
            } else if (!isPause && pauseWindowStartMs != null) {
                paused += (entry.enteredAtMs - pauseWindowStartMs)
                pauseWindowStartMs = null
            }
        }

        // Open pause window: still in a pause status now
        if (pauseWindowStartMs != null) {
            paused += (nowMs - pauseWindowStartMs)
        }

        return paused.coerceAtLeast(0L)
    }

    /**
     * Compute remaining percentage (0..100). May be negative when breached.
     *
     * Returns 100 when no SLA is defined ([Long.MAX_VALUE] remaining).
     */
    fun remainingPct(
        createdAtMs: Long,
        nowMs: Long,
        sla: SlaDefinitionDto,
        statusHistory: List<StatusHistoryEntry>,
    ): Int {
        val budgetMs = sla.repairMinutes?.let { it.toLong() * 60_000L }
            ?: return 100
        if (budgetMs <= 0L) return 0

        val rem = remainingMs(createdAtMs, nowMs, sla, statusHistory)
        return ((rem.toDouble() / budgetMs.toDouble()) * 100.0).toInt()
    }

    /**
     * Determine [SlaTier] from remaining percentage.
     *
     * - > 25 %  → [SlaTier.Green]
     * - ≤ 25 % and > 0 % → [SlaTier.Amber]
     * - ≤ 0 %  → [SlaTier.Red]
     */
    fun tier(remainingPct: Int): SlaTier = when {
        remainingPct > 25  -> SlaTier.Green
        remainingPct > 0   -> SlaTier.Amber
        else               -> SlaTier.Red
    }

    /**
     * Project the epoch ms at which the SLA deadline will be breached.
     *
     * Returns null when no SLA is defined or when the deadline has already passed.
     */
    fun projectedBreachMs(
        createdAtMs: Long,
        nowMs: Long,
        sla: SlaDefinitionDto,
        statusHistory: List<StatusHistoryEntry>,
    ): Long? {
        val budgetMs = sla.repairMinutes?.let { it.toLong() * 60_000L } ?: return null
        val rem = remainingMs(createdAtMs, nowMs, sla, statusHistory)
        if (rem <= 0L) return null
        return nowMs + rem
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    private fun isPauseStatus(name: String?): Boolean {
        val norm = name?.trim()?.lowercase() ?: return false
        return PAUSE_STATUS_PATTERNS.any { pattern -> norm.contains(pattern) }
    }
}
