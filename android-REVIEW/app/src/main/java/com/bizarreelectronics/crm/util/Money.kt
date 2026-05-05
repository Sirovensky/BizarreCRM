package com.bizarreelectronics.crm.util

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * Money helpers: all monetary values in Room entities are stored as [Long] cents
 * to eliminate IEEE-754 drift that corrupts totals on Double columns.
 *
 * Convention: a value of 1234 represents $12.34.
 *
 * Conversion rules:
 *  - When reading from an API payload (nullable Double dollars) use [Double?.toCentsOrZero].
 *  - When passing cents to a server endpoint that expects dollars, use [Long.toDollars].
 *  - For UI display, use [Long.formatAsMoney] — it always produces exactly two decimals
 *    with no rounding drift.
 *
 * The conversion pivots through BigDecimal to avoid accumulating floating-point
 * error during the dollars→cents step (e.g. 0.1 + 0.2).
 */

/** Convert dollars (Double) to cents (Long) using banker's rounding to 2 decimals. */
fun Double.toCents(): Long =
    BigDecimal.valueOf(this).movePointRight(2).setScale(0, RoundingMode.HALF_EVEN).toLong()

/** Null-safe dollars→cents — treats null/NaN/Infinity as 0 cents. */
fun Double?.toCentsOrZero(): Long {
    if (this == null || this.isNaN() || this.isInfinite()) return 0L
    return this.toCents()
}

/** Convert cents (Long) back to dollars (Double) for legacy call sites. */
fun Long.toDollars(): Double = this / 100.0

/** Format cents as a "$12.34" display string with no rounding drift. */
fun Long.formatAsMoney(): String {
    val sign = if (this < 0) "-" else ""
    val abs = kotlin.math.abs(this)
    val whole = abs / 100
    val cents = abs % 100
    val centsStr = cents.toString().padStart(2, '0')
    return "${sign}${'$'}${whole}.${centsStr}"
}

/** Same as [formatAsMoney] but without the leading "$" — useful for table cells. */
fun Long.formatAsAmount(): String {
    val sign = if (this < 0) "-" else ""
    val abs = kotlin.math.abs(this)
    val whole = abs / 100
    val cents = abs % 100
    val centsStr = cents.toString().padStart(2, '0')
    return "${sign}${whole}.${centsStr}"
}
