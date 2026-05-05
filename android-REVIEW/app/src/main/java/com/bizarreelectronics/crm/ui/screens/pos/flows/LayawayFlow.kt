package com.bizarreelectronics.crm.ui.screens.pos.flows

import com.bizarreelectronics.crm.ui.screens.pos.CartLine

// ─── Result types ─────────────────────────────────────────────────────────────

/** Result of [LayawayFlow.validate]. */
sealed class LayawayValidation {
    /** Deposit meets or exceeds the minimum requirement. */
    object Ok : LayawayValidation()

    /**
     * Deposit is below the required minimum.
     *
     * @param requiredCents  Minimum deposit in cents that must be collected
     *   (20% of [totalCents], rounded up to the nearest cent).
     */
    data class BelowMinimum(val requiredCents: Long) : LayawayValidation()
}

/**
 * Specification returned by [LayawayFlow.create], ready to be submitted to
 * the layaway endpoint (Wave 2).
 *
 * @param items         Full cart lines held for this layaway.
 * @param totalCents    Grand total of all items.
 * @param depositCents  Deposit collected at time of layaway creation.
 * @param balanceCents  Remaining balance due before pickup.
 */
data class LayawaySaleSpec(
    val items: List<CartLine>,
    val totalCents: Long,
    val depositCents: Long,
    val balanceCents: Long,
)

// ─── Flow ─────────────────────────────────────────────────────────────────────

/**
 * Entry point for layaway (hold-and-pay-over-time) transactions.
 *
 * When to use: the customer wants to reserve items but cannot pay in full
 * today.  A minimum deposit of **20%** of the cart total is required at
 * the time of layaway creation; the balance is collected on pickup.
 *
 * Business rules enforced here:
 * - Minimum deposit = ceil(totalCents × 20 / 100).
 * - No partial-percent tricks: integer arithmetic keeps everything in cents.
 *
 * Wave 2 will wire [create] into a dedicated LayawayScreen and link the
 * resulting [LayawaySaleSpec] to a new layaway ticket type on the server.
 */
object LayawayFlow {

    private const val MIN_DEPOSIT_PCT = 20L   // 20%

    /**
     * Validate that [depositCents] satisfies the minimum deposit rule.
     *
     * @param totalCents    Full cart total in cents.
     * @param depositCents  Proposed deposit in cents.
     * @return [LayawayValidation.Ok] or [LayawayValidation.BelowMinimum].
     */
    fun validate(totalCents: Long, depositCents: Long): LayawayValidation {
        // Ceiling division: round up to nearest cent so partial-cent totals
        // always require the higher deposit.
        val required = (totalCents * MIN_DEPOSIT_PCT + 99L) / 100L
        return if (depositCents >= required) {
            LayawayValidation.Ok
        } else {
            LayawayValidation.BelowMinimum(requiredCents = required)
        }
    }

    /**
     * Build a [LayawaySaleSpec] after a successful [validate] check.
     *
     * Callers should call [validate] first and only proceed if [LayawayValidation.Ok]
     * is returned; this function does not re-validate.
     *
     * @param items         Lines to hold for the customer.
     * @param depositCents  Deposit amount collected now.
     * @return              Spec ready for the layaway creation endpoint.
     */
    fun create(items: List<CartLine>, depositCents: Long): LayawaySaleSpec {
        val total = items.sumOf { it.lineTotalCents }
        return LayawaySaleSpec(
            items = items,
            totalCents = total,
            depositCents = depositCents,
            balanceCents = (total - depositCents).coerceAtLeast(0L),
        )
    }
}
