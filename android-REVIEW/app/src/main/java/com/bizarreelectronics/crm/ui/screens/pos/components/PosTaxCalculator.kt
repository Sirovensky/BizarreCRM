package com.bizarreelectronics.crm.ui.screens.pos.components

import com.bizarreelectronics.crm.ui.screens.pos.AttachedCustomer
import com.bizarreelectronics.crm.ui.screens.pos.CartLine
import com.bizarreelectronics.crm.ui.screens.pos.PosCartState
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode

// ─── Rounding ────────────────────────────────────────────────────────────────

/**
 * Rounding strategy applied per-jurisdiction when converting fractional
 * cent amounts to whole cents.
 */
enum class RoundingRule {
    HALF_UP,
    HALF_DOWN,
    BANKERS;

    fun apply(value: BigDecimal, scale: Int = 0): BigDecimal = when (this) {
        HALF_UP   -> value.setScale(scale, RoundingMode.HALF_UP)
        HALF_DOWN -> value.setScale(scale, RoundingMode.HALF_DOWN)
        BANKERS   -> value.setScale(scale, RoundingMode.HALF_EVEN)
    }
}

// ─── Tax config ──────────────────────────────────────────────────────────────

/**
 * A single tax jurisdiction (state, county, city, special district, etc.).
 *
 * @param jurisdictionId   Stable identifier used as map key in results.
 * @param name             Human-readable label for receipts/UI.
 * @param rateBps          Rate in basis points (100 bps = 1.00%).
 * @param applicableTaxClassIds  When non-null, jurisdiction only applies to
 *   cart lines whose [CartLine.taxClassId] is in this set.  Null = applies to
 *   all lines.
 */
data class JurisdictionRule(
    val jurisdictionId: String,
    val name: String,
    val rateBps: Int,
    val applicableTaxClassIds: Set<Long>? = null,
)

/**
 * Full tax configuration for one tenant/location.
 *
 * @param jurisdictions        Ordered list of jurisdictions to apply.
 * @param rounding             How fractional cents are rounded (default HALF_UP).
 * @param cartOverrideRateBps  When non-null, each jurisdiction uses this rate
 *   instead of its own [JurisdictionRule.rateBps].  Useful for flat-rate or
 *   special-event overrides.
 */
data class TenantTaxConfig(
    val jurisdictions: List<JurisdictionRule>,
    val rounding: RoundingRule = RoundingRule.HALF_UP,
    val cartOverrideRateBps: Int? = null,
)

// ─── Result types ─────────────────────────────────────────────────────────────

/** Per-line tax result. */
data class LineTaxResult(
    val lineId: String,
    val taxCents: Long,
    val exempt: Boolean,
)

/** Per-jurisdiction aggregate. */
data class JurisdictionTaxResult(
    val jurisdictionId: String,
    val name: String,
    val taxCents: Long,
)

/** Full tax breakdown returned by [PosTaxCalculator.calculate]. */
data class TaxBreakdown(
    val lines: List<LineTaxResult>,
    val jurisdictions: List<JurisdictionTaxResult>,
    val totalTaxCents: Long,
)

// ─── Calculator ───────────────────────────────────────────────────────────────

/**
 * Pure, stateless tax engine.  No Android/Room/Hilt dependencies — safe to
 * call from unit tests and from Compose previews.
 *
 * [AttachedCustomer] and [PosCartState] are defined in the parent `pos`
 * package (`PosModels.kt`) so that unit tests in the same package can
 * reference them without a qualified import.
 *
 * ## Algorithm
 * 1. If [customerTaxExempt] is true (or [PosCartState.customer.taxExempt]) →
 *    return a zero breakdown immediately.
 * 2. For each [JurisdictionRule]:
 *    a. Determine effective rate: [TenantTaxConfig.cartOverrideRateBps] if set,
 *       otherwise the jurisdiction's own [JurisdictionRule.rateBps].
 *    b. For each cart line that passes the jurisdiction's class filter, compute
 *       `lineTax = applyRounding(line.lineTotalCents, effectiveRateBps, rounding)`.
 *    c. Sum line taxes to get jurisdiction total.
 * 3. Aggregate jurisdiction totals into [TaxBreakdown].
 */
object PosTaxCalculator {

    /**
     * Compute tax for every line in [cart] under [config].
     *
     * @param cart               Lines and (optional) attached customer.
     * @param config             Jurisdictions, rounding, and any override rate.
     * @param customerTaxExempt  Pass `true` to force exempt regardless of
     *   [PosCartState.customer].  Defaults to `false`; the customer flag on
     *   the cart object is also honored.
     */
    fun calculate(
        cart: PosCartState,
        config: TenantTaxConfig,
        customerTaxExempt: Boolean = false,
    ): TaxBreakdown {
        val exempt = customerTaxExempt || (cart.customer?.taxExempt == true)

        if (cart.lines.isEmpty()) {
            return TaxBreakdown(
                lines = emptyList(),
                jurisdictions = emptyList(),
                totalTaxCents = 0L,
            )
        }

        if (exempt) {
            return TaxBreakdown(
                lines = cart.lines.map { LineTaxResult(it.id, taxCents = 0L, exempt = true) },
                jurisdictions = config.jurisdictions.map {
                    JurisdictionTaxResult(it.jurisdictionId, it.name, 0L)
                },
                totalTaxCents = 0L,
            )
        }

        // Per-line totals accumulated per jurisdiction then merged into lineTaxAccum.
        val lineTaxAccum: MutableMap<String, Long> = mutableMapOf()
        cart.lines.forEach { lineTaxAccum[it.id] = 0L }

        val jurisdictionResults = config.jurisdictions.map { jurisdiction ->
            val effectiveRateBps = config.cartOverrideRateBps ?: jurisdiction.rateBps

            var jurisdictionTotal = 0L
            for (line in cart.lines) {
                // Apply class filter: skip lines whose taxClassId is not in the set.
                if (jurisdiction.applicableTaxClassIds != null) {
                    val lineClass = line.taxClassId
                    if (lineClass == null || lineClass !in jurisdiction.applicableTaxClassIds) {
                        continue
                    }
                }

                val lineTax = applyRounding(
                    amountCents = line.lineTotalCents,
                    rateBps = effectiveRateBps,
                    rule = config.rounding,
                )
                jurisdictionTotal += lineTax
                lineTaxAccum[line.id] = (lineTaxAccum[line.id] ?: 0L) + lineTax
            }

            JurisdictionTaxResult(
                jurisdictionId = jurisdiction.jurisdictionId,
                name = jurisdiction.name,
                taxCents = jurisdictionTotal,
            )
        }

        val lineResults = cart.lines.map { line ->
            LineTaxResult(
                lineId = line.id,
                taxCents = lineTaxAccum[line.id] ?: 0L,
                exempt = false,
            )
        }

        return TaxBreakdown(
            lines = lineResults,
            jurisdictions = jurisdictionResults,
            totalTaxCents = jurisdictionResults.sumOf { it.taxCents },
        )
    }

    /**
     * Apply [rule] rounding to `amountCents * rateBps / 10000`, returning a
     * whole-cent Long.
     *
     * Exposed as a top-level helper so tests can exercise rounding in isolation.
     */
    fun applyRounding(amountCents: Long, rateBps: Int, rule: RoundingRule): Long {
        val raw = BigDecimal(amountCents)
            .multiply(BigDecimal(rateBps))
            .divide(BigDecimal(10_000), MathContext.DECIMAL128)
        return rule.apply(raw, scale = 0).toLong()
    }
}
