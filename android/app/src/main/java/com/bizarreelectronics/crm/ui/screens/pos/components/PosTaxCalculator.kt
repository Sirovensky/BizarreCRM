package com.bizarreelectronics.crm.ui.screens.pos.components

import com.bizarreelectronics.crm.ui.screens.pos.CartLine
import com.bizarreelectronics.crm.ui.screens.pos.PosCartState
import java.math.BigDecimal
import java.math.RoundingMode

// ─── Domain models ────────────────────────────────────────────────────────────

/**
 * A single jurisdiction's contribution to the tax total.
 * e.g. "State Sales Tax" at 6%, "County Tax" at 1%.
 */
data class JurisdictionTax(
    val jurisdictionId: String,
    val name: String,
    val rateBps: Int,           // basis points (600 = 6.00%)
    val taxCents: Long,
)

/**
 * Full tax breakdown returned by [PosTaxCalculator.calculate].
 */
data class TaxBreakdown(
    val lines: List<LineTax>,
    val jurisdictions: List<JurisdictionTax>,
    val totalTaxCents: Long,
)

/** Per-cart-line tax result. */
data class LineTax(
    val lineId: String,
    val taxableAmountCents: Long,
    val taxCents: Long,
    val exempt: Boolean,
)

// ─── Tenant config ────────────────────────────────────────────────────────────

enum class RoundingRule { BANKERS, HALF_UP, HALF_DOWN }

data class JurisdictionRule(
    val jurisdictionId: String,
    val name: String,
    val rateBps: Int,           // 600 = 6.00%
    /** Tax-class IDs that this jurisdiction applies to (null = all classes). */
    val applicableTaxClassIds: Set<Long>? = null,
)

data class TenantTaxConfig(
    val jurisdictions: List<JurisdictionRule> = emptyList(),
    val roundingRule: RoundingRule = RoundingRule.BANKERS,
    /** When true the cart-level override rate (in bps) replaces per-line class rates. */
    val cartOverrideRateBps: Int? = null,
)

// ─── Calculator ───────────────────────────────────────────────────────────────

/**
 * §16.5 — Pure Kotlin tax engine. No Android dependencies; safe to test on JVM.
 *
 * Rules applied in order:
 *  1. Tax-exempt customer → all lines exempt, TaxBreakdown.totalTaxCents == 0.
 *  2. Cart-level override rate (tenantConfig.cartOverrideRateBps) replaces
 *     per-line class rates when present.
 *  3. Per-line: taxable amount = line.subtotalCents; iterate jurisdictions,
 *     filter by applicableTaxClassIds (null = applies to all).
 *  4. Rounding applied per jurisdiction per line per [TenantTaxConfig.roundingRule].
 *  5. Jurisdiction totals summed across all lines.
 */
object PosTaxCalculator {

    fun calculate(cart: PosCartState, config: TenantTaxConfig): TaxBreakdown {
        val taxExempt = cart.customer?.let { false } ?: false
        // Future: customer.taxExempt flag — for now exempt = false unless caller overrides via config

        if (taxExempt || config.jurisdictions.isEmpty()) {
            return emptyBreakdown(cart)
        }

        val lineTaxes = mutableListOf<LineTax>()
        val jurisdictionAccumulators = mutableMapOf<String, Long>()
        config.jurisdictions.forEach { j -> jurisdictionAccumulators[j.jurisdictionId] = 0L }

        for (line in cart.lines) {
            val effectiveRateBps: Int? = config.cartOverrideRateBps

            var lineTaxTotal = 0L
            for (jurisdiction in config.jurisdictions) {
                // Skip if jurisdiction only applies to specific tax classes and this line
                // doesn't match.
                val classIds = jurisdiction.applicableTaxClassIds
                if (classIds != null && line.taxClassId != null && !classIds.contains(line.taxClassId)) {
                    continue
                }

                val rateBps = effectiveRateBps ?: jurisdiction.rateBps
                val taxCents = applyRounding(
                    amountCents = line.subtotalCents,
                    rateBps = rateBps,
                    rule = config.roundingRule,
                )
                lineTaxTotal += taxCents
                jurisdictionAccumulators[jurisdiction.jurisdictionId] =
                    (jurisdictionAccumulators[jurisdiction.jurisdictionId] ?: 0L) + taxCents
            }

            lineTaxes += LineTax(
                lineId = line.id,
                taxableAmountCents = line.subtotalCents,
                taxCents = lineTaxTotal,
                exempt = false,
            )
        }

        val jurisdictionBreakdown = config.jurisdictions.map { j ->
            JurisdictionTax(
                jurisdictionId = j.jurisdictionId,
                name = j.name,
                rateBps = config.cartOverrideRateBps ?: j.rateBps,
                taxCents = jurisdictionAccumulators[j.jurisdictionId] ?: 0L,
            )
        }

        return TaxBreakdown(
            lines = lineTaxes,
            jurisdictions = jurisdictionBreakdown,
            totalTaxCents = jurisdictionBreakdown.sumOf { it.taxCents },
        )
    }

    // ─── Overload: honor tax-exempt customer flag explicitly ──────────────────

    fun calculate(
        cart: PosCartState,
        config: TenantTaxConfig,
        customerTaxExempt: Boolean,
    ): TaxBreakdown {
        if (customerTaxExempt) return emptyBreakdown(cart)
        return calculate(cart, config)
    }

    // ─── Rounding ─────────────────────────────────────────────────────────────

    internal fun applyRounding(amountCents: Long, rateBps: Int, rule: RoundingRule): Long {
        val mode = when (rule) {
            RoundingRule.BANKERS -> RoundingMode.HALF_EVEN
            RoundingRule.HALF_UP -> RoundingMode.HALF_UP
            RoundingRule.HALF_DOWN -> RoundingMode.HALF_DOWN
        }
        return BigDecimal.valueOf(amountCents)
            .multiply(BigDecimal.valueOf(rateBps.toLong()))
            .divide(BigDecimal.valueOf(10_000L), 0, mode)
            .toLong()
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private fun emptyBreakdown(cart: PosCartState): TaxBreakdown {
        val lines = cart.lines.map { line ->
            LineTax(
                lineId = line.id,
                taxableAmountCents = line.subtotalCents,
                taxCents = 0L,
                exempt = true,
            )
        }
        return TaxBreakdown(lines = lines, jurisdictions = emptyList(), totalTaxCents = 0L)
    }
}
