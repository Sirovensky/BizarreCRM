package com.bizarreelectronics.crm.ui.screens.pos

import com.bizarreelectronics.crm.ui.screens.pos.components.JurisdictionRule
import com.bizarreelectronics.crm.ui.screens.pos.components.PosTaxCalculator
import com.bizarreelectronics.crm.ui.screens.pos.components.RoundingRule
import com.bizarreelectronics.crm.ui.screens.pos.components.TenantTaxConfig
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for [PosTaxCalculator].
 *
 * Pure JVM — no Android, Room, or Hilt dependencies.
 * Covers:
 *  1. Single-jurisdiction basic tax
 *  2. Multi-jurisdiction breakdown (state + county)
 *  3. Tax-exempt customer flag → zero tax
 *  4. Rounding: BANKERS (half-even)
 *  5. Rounding: HALF_UP
 *  6. Rounding: HALF_DOWN
 *  7. Line-level tax class filter (jurisdiction skips non-matching class)
 *  8. Cart-level override rate replaces per-line rates
 *  9. Empty cart → zero breakdown
 * 10. Multiple lines with different tax classes
 * 11. Cart override + exempt customer → exempt wins
 * 12. Jurisdiction total aggregates across lines
 *
 * Plan §16.5 L1815-L1818 / ActionPlan unit test requirement.
 */
class PosTaxEngineTest {

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private fun line(
        name: String = "Item",
        unitPriceCents: Long,
        qty: Int = 1,
        discountCents: Long = 0L,
        taxClassId: Long? = null,
    ) = CartLine(
        name = name,
        unitPriceCents = unitPriceCents,
        qty = qty,
        discountCents = discountCents,
        taxClassId = taxClassId,
    )

    private fun cart(vararg lines: CartLine, customer: AttachedCustomer? = null) =
        PosCartState(lines = lines.toList(), customer = customer)

    private val stateJurisdiction = JurisdictionRule(
        jurisdictionId = "state",
        name = "State Sales Tax",
        rateBps = 600,   // 6.00%
    )

    private val countyJurisdiction = JurisdictionRule(
        jurisdictionId = "county",
        name = "County Tax",
        rateBps = 100,   // 1.00%
    )

    private val baseConfig = TenantTaxConfig(
        jurisdictions = listOf(stateJurisdiction, countyJurisdiction),
    )

    // ─── 1. Single-jurisdiction basic tax ────────────────────────────────────

    @Test
    fun `single jurisdiction 6pct on 10000 cents produces 600 cents tax`() {
        val config = TenantTaxConfig(jurisdictions = listOf(stateJurisdiction))
        val c = cart(line(unitPriceCents = 10_000))
        val result = PosTaxCalculator.calculate(c, config)
        assertEquals(600L, result.totalTaxCents)
    }

    // ─── 2. Multi-jurisdiction breakdown ─────────────────────────────────────

    @Test
    fun `multi-jurisdiction state plus county sums correctly`() {
        val c = cart(line(unitPriceCents = 10_000))
        val result = PosTaxCalculator.calculate(c, baseConfig)
        // State: 10000 * 600/10000 = 600
        // County: 10000 * 100/10000 = 100
        assertEquals(700L, result.totalTaxCents)
        assertEquals(2, result.jurisdictions.size)
        assertEquals(600L, result.jurisdictions.first { it.jurisdictionId == "state" }.taxCents)
        assertEquals(100L, result.jurisdictions.first { it.jurisdictionId == "county" }.taxCents)
    }

    // ─── 3. Tax-exempt customer flag ─────────────────────────────────────────

    @Test
    fun `tax-exempt true results in zero tax for all lines`() {
        val c = cart(line(unitPriceCents = 10_000))
        val result = PosTaxCalculator.calculate(c, baseConfig, customerTaxExempt = true)
        assertEquals(0L, result.totalTaxCents)
        result.lines.forEach { lineTax ->
            assertEquals(0L, lineTax.taxCents)
            assertEquals(true, lineTax.exempt)
        }
    }

    // ─── 4. Rounding: BANKERS (half-even) ────────────────────────────────────

    @Test
    fun `bankers rounding rounds half to even`() {
        // 1 cent * 500 bps / 10000 = 0.05 → rounds to 0 (banker's: nearest even = 0)
        val cents = PosTaxCalculator.applyRounding(1L, 500, RoundingRule.BANKERS)
        assertEquals(0L, cents)
    }

    @Test
    fun `bankers rounding rounds 3 cents at 500 bps to 0`() {
        // 3 * 500 / 10000 = 0.15 → rounds to 0 (nearest even)
        val cents = PosTaxCalculator.applyRounding(3L, 500, RoundingRule.BANKERS)
        assertEquals(0L, cents)
    }

    @Test
    fun `bankers rounding on standard amount is accurate`() {
        // 10000 * 600 / 10000 = 600.0 exactly
        val cents = PosTaxCalculator.applyRounding(10_000L, 600, RoundingRule.BANKERS)
        assertEquals(600L, cents)
    }

    // ─── 5. Rounding: HALF_UP ────────────────────────────────────────────────

    @Test
    fun `half-up rounding rounds 0_5 up`() {
        // 1 * 5000 / 10000 = 0.5 → rounds up to 1
        val cents = PosTaxCalculator.applyRounding(1L, 5000, RoundingRule.HALF_UP)
        assertEquals(1L, cents)
    }

    // ─── 6. Rounding: HALF_DOWN ──────────────────────────────────────────────

    @Test
    fun `half-down rounding rounds 0_5 down`() {
        // 1 * 5000 / 10000 = 0.5 → rounds down to 0
        val cents = PosTaxCalculator.applyRounding(1L, 5000, RoundingRule.HALF_DOWN)
        assertEquals(0L, cents)
    }

    // ─── 7. Line-level tax class filter ──────────────────────────────────────

    @Test
    fun `jurisdiction with class filter skips lines with non-matching tax class`() {
        val foodJurisdiction = JurisdictionRule(
            jurisdictionId = "food_tax",
            name = "Food Tax",
            rateBps = 200,
            applicableTaxClassIds = setOf(1L),   // only applies to class 1
        )
        val config = TenantTaxConfig(jurisdictions = listOf(foodJurisdiction))
        // Line with class 2 — food tax should NOT apply
        val c = cart(line(unitPriceCents = 10_000, taxClassId = 2L))
        val result = PosTaxCalculator.calculate(c, config)
        assertEquals(0L, result.totalTaxCents)
    }

    @Test
    fun `jurisdiction with class filter applies to matching class`() {
        val foodJurisdiction = JurisdictionRule(
            jurisdictionId = "food_tax",
            name = "Food Tax",
            rateBps = 200,
            applicableTaxClassIds = setOf(1L),
        )
        val config = TenantTaxConfig(jurisdictions = listOf(foodJurisdiction))
        val c = cart(line(unitPriceCents = 10_000, taxClassId = 1L))
        val result = PosTaxCalculator.calculate(c, config)
        // 10000 * 200 / 10000 = 200
        assertEquals(200L, result.totalTaxCents)
    }

    // ─── 8. Cart-level override rate ─────────────────────────────────────────

    @Test
    fun `cart override rate replaces per-jurisdiction rates`() {
        val config = baseConfig.copy(cartOverrideRateBps = 800)  // 8% override
        val c = cart(line(unitPriceCents = 10_000))
        val result = PosTaxCalculator.calculate(c, config)
        // Both jurisdictions use 8% override: 2 * (10000 * 800 / 10000) = 2 * 800 = 1600
        assertEquals(1_600L, result.totalTaxCents)
    }

    // ─── 9. Empty cart → zero breakdown ──────────────────────────────────────

    @Test
    fun `empty cart produces zero tax breakdown`() {
        val c = PosCartState()
        val result = PosTaxCalculator.calculate(c, baseConfig)
        assertEquals(0L, result.totalTaxCents)
        assertEquals(true, result.lines.isEmpty())
    }

    // ─── 10. Multiple lines different tax classes ─────────────────────────────

    @Test
    fun `multiple lines with different tax classes compute independently`() {
        val electronics = JurisdictionRule("elec", "Electronics Tax", rateBps = 900,
            applicableTaxClassIds = setOf(10L))
        val clothing = JurisdictionRule("cloth", "Clothing Tax", rateBps = 0,
            applicableTaxClassIds = setOf(20L))
        val config = TenantTaxConfig(jurisdictions = listOf(electronics, clothing))

        val c = cart(
            line(unitPriceCents = 10_000, taxClassId = 10L),   // electronics: 900 tax
            line(unitPriceCents = 5_000, taxClassId = 20L),    // clothing: 0 tax
        )
        val result = PosTaxCalculator.calculate(c, config)
        // Electronics: 10000 * 900/10000 = 900; Clothing: 0
        assertEquals(900L, result.totalTaxCents)
    }

    // ─── 11. Cart override + exempt wins ─────────────────────────────────────

    @Test
    fun `exempt customer beats cart override rate`() {
        val config = baseConfig.copy(cartOverrideRateBps = 1000)
        val c = cart(line(unitPriceCents = 10_000))
        val result = PosTaxCalculator.calculate(c, config, customerTaxExempt = true)
        assertEquals(0L, result.totalTaxCents)
    }

    // ─── 12. Jurisdiction total aggregates across lines ───────────────────────

    @Test
    fun `jurisdiction tax totals sum across all cart lines`() {
        val config = TenantTaxConfig(jurisdictions = listOf(stateJurisdiction))
        val c = cart(
            line(unitPriceCents = 10_000),   // 600
            line(unitPriceCents = 5_000),    // 300
            line(unitPriceCents = 2_000),    // 120
        )
        val result = PosTaxCalculator.calculate(c, config)
        assertEquals(1_020L, result.totalTaxCents)
        assertEquals(1_020L, result.jurisdictions.first().taxCents)
    }
}
