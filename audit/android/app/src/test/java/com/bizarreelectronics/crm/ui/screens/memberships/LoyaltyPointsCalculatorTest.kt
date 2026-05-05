package com.bizarreelectronics.crm.ui.screens.memberships

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pure-JVM unit tests for loyalty-points accrual rules (§38.3 / §38.6).
 *
 * Points are earned on net sale totals (after discounts, before tax).
 * Tier-multiplier schedule:
 *   Basic  → 1 pt per \$1  (1.0×)
 *   Silver → 2 pts per \$1 (2.0×)
 *   Gold   → 3 pts per \$1 (3.0×)
 *
 * Fractional cents are truncated (floor) to whole points.
 *
 * No Android context or mocks required — all logic is pure math.
 */
class LoyaltyPointsCalculatorTest {

    // ─── Calculator under test ────────────────────────────────────────────────

    /**
     * Calculates loyalty points for a sale.
     *
     * @param netCents  net sale amount in cents (≥ 0)
     * @param tierName  "Basic" | "Silver" | "Gold" (case-insensitive)
     * @return          whole points earned (floor)
     */
    private fun calculatePoints(netCents: Long, tierName: String): Int {
        if (netCents <= 0L) return 0
        val multiplier = when (tierName.lowercase()) {
            "silver" -> 2.0
            "gold"   -> 3.0
            else     -> 1.0          // Basic and unknown tiers
        }
        // 1 pt per $1, multiplied by tier
        return ((netCents / 100.0) * multiplier).toInt()
    }

    // ─── Basic tier ───────────────────────────────────────────────────────────

    @Test fun basic_zeroDollars_returnsZeroPoints() {
        assertEquals(0, calculatePoints(0L, "Basic"))
    }

    @Test fun basic_oneHundredCents_returnsOnePoint() {
        assertEquals(1, calculatePoints(100L, "Basic"))
    }

    @Test fun basic_fiveHundredCents_returnsFivePoints() {
        assertEquals(5, calculatePoints(500L, "Basic"))
    }

    @Test fun basic_fractionalDollar_floorsToWholePoints() {
        // $1.50 → 1 pt (truncated, not rounded)
        assertEquals(1, calculatePoints(150L, "Basic"))
    }

    @Test fun basic_negativeCents_returnsZeroPoints() {
        assertEquals(0, calculatePoints(-100L, "Basic"))
    }

    // ─── Silver tier (2×) ─────────────────────────────────────────────────────

    @Test fun silver_oneHundredCents_returnsTwoPoints() {
        assertEquals(2, calculatePoints(100L, "Silver"))
    }

    @Test fun silver_twoFiftyDollars_returnsFivePoints() {
        // $2.50 × 2 = 5 pts
        assertEquals(5, calculatePoints(250L, "Silver"))
    }

    @Test fun silver_caseInsensitive() {
        assertEquals(2, calculatePoints(100L, "silver"))
    }

    // ─── Gold tier (3×) ───────────────────────────────────────────────────────

    @Test fun gold_oneHundredCents_returnsThreePoints() {
        assertEquals(3, calculatePoints(100L, "Gold"))
    }

    @Test fun gold_oneThousandCents_returnsThirtyPoints() {
        assertEquals(30, calculatePoints(1_000L, "Gold"))
    }

    @Test fun gold_caseInsensitive() {
        assertEquals(3, calculatePoints(100L, "GOLD"))
    }

    // ─── Unknown tier falls back to Basic ────────────────────────────────────

    @Test fun unknownTier_treatedAsBasic() {
        assertEquals(1, calculatePoints(100L, "Platinum"))
    }

    // ─── Large amounts ────────────────────────────────────────────────────────

    @Test fun gold_largeRepairBill_correctPoints() {
        // $250 repair × 3 = 750 pts
        assertEquals(750, calculatePoints(25_000L, "Gold"))
    }
}
