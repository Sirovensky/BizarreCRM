package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * §31.1 — unit coverage for the Money helpers. Monetary math on IEEE-754
 * doubles is a classic source of penny-off drift; these tests lock the
 * BigDecimal / banker's-rounding pivot in place.
 */
class MoneyTest {

    // --- Double.toCents ------------------------------------------------------

    @Test fun `toCents rounds banker half-to-even`() {
        // HALF_EVEN: 0.005 → 0 cents (rounds to even 0), not 1.
        assertEquals(0L, 0.005.toCents())
        assertEquals(2L, 0.015.toCents())   // rounds to even 2
        assertEquals(2L, 0.025.toCents())   // rounds to even 2
        assertEquals(4L, 0.035.toCents())   // rounds to even 4
    }

    @Test fun `toCents handles classic float drift`() {
        // Canonical 0.1 + 0.2 trap — pivoting through BigDecimal avoids the
        // 0.30000000000000004 double.
        assertEquals(30L, (0.1 + 0.2).toCents())
    }

    @Test fun `toCents preserves sign`() {
        assertEquals(-1234L, (-12.34).toCents())
        assertEquals(1234L, 12.34.toCents())
    }

    // --- Double toCentsOrZero -----------------------------------------------

    @Test fun `toCentsOrZero returns 0 for null NaN and Infinity`() {
        val nullDouble: Double? = null
        assertEquals(0L, nullDouble.toCentsOrZero())
        assertEquals(0L, Double.NaN.toCentsOrZero())
        assertEquals(0L, Double.POSITIVE_INFINITY.toCentsOrZero())
        assertEquals(0L, Double.NEGATIVE_INFINITY.toCentsOrZero())
    }

    @Test fun `toCentsOrZero on a valid value delegates to toCents`() {
        val value: Double? = 45.67
        assertEquals(4567L, value.toCentsOrZero())
    }

    // --- Long.toDollars ------------------------------------------------------

    @Test fun `toDollars divides by 100`() {
        assertEquals(12.34, 1234L.toDollars(), 0.0001)
        assertEquals(0.0, 0L.toDollars(), 0.0001)
        assertEquals(-0.05, (-5L).toDollars(), 0.0001)
    }

    // --- Long.formatAsMoney / formatAsAmount --------------------------------

    @Test fun `formatAsMoney renders two decimals with leading dollar sign`() {
        assertEquals("$12.34", 1234L.formatAsMoney())
        assertEquals("$0.00", 0L.formatAsMoney())
        assertEquals("$0.05", 5L.formatAsMoney())           // cents padded
        assertEquals("$1000.00", 100000L.formatAsMoney())   // no thousands separator (intentional)
    }

    @Test fun `formatAsMoney handles negative amounts`() {
        assertEquals("-$12.34", (-1234L).formatAsMoney())
        assertEquals("-$0.01", (-1L).formatAsMoney())
    }

    @Test fun `formatAsAmount drops the dollar sign`() {
        assertEquals("12.34", 1234L.formatAsAmount())
        assertEquals("-0.99", (-99L).formatAsAmount())
        assertEquals("0.00", 0L.formatAsAmount())
    }
}
