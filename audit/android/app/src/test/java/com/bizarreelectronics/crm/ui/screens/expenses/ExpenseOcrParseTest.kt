package com.bizarreelectronics.crm.ui.screens.expenses

import com.bizarreelectronics.crm.ui.screens.expenses.components.ReceiptOcrScanner
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for [ReceiptOcrScanner.parseReceiptText].
 * Uses stub receipt text — no Android or ML Kit runtime required.
 */
class ExpenseOcrParseTest {

    // ── Stub 1: Typical US grocery receipt ────────────────────────────

    @Test
    fun `parse grocery receipt extracts total vendor and date`() {
        val raw = """
            WHOLE FOODS MARKET
            123 Main St, Austin TX
            04/22/2026

            Bananas          1.29
            Bread            3.49
            Coffee          12.99

            Subtotal        17.77
            Tax              1.42
            Total           19.19

            THANK YOU FOR SHOPPING WITH US
        """.trimIndent()

        val result = ReceiptOcrScanner.parseReceiptText(raw)

        assertEquals("19.19", result.total)
        assertNotNull(result.vendor)
        // Vendor should be the first non-numeric, non-blank line
        assertEquals("WHOLE FOODS MARKET", result.vendor)
        assertNotNull(result.date)
        // Date should be extracted from the slash-format line
        assertEquals("04/22/2026", result.date)
    }

    // ── Stub 2: Hardware store receipt with ISO date ──────────────────

    @Test
    fun `parse hardware store receipt with ISO date`() {
        val raw = """
            ACE HARDWARE
            2026-03-15

            Screwdriver Set   14.99
            Electrical Tape    3.29

            Grand Total       18.28

            Payment: VISA *4321
        """.trimIndent()

        val result = ReceiptOcrScanner.parseReceiptText(raw)

        assertEquals("18.28", result.total)
        assertEquals("ACE HARDWARE", result.vendor)
        assertEquals("2026-03-15", result.date)
    }

    // ── Stub 3: Restaurant receipt — no total keyword match, amount fallback ──

    @Test
    fun `parse restaurant receipt with written month date`() {
        val raw = """
            THE RUSTIC SPOON
            April 21, 2026

            Burger            15.00
            Fries              4.50
            Lemonade           3.75

            Total Due: 23.25

            Tip: _______
        """.trimIndent()

        val result = ReceiptOcrScanner.parseReceiptText(raw)

        assertEquals("23.25", result.total)
        assertNotNull(result.vendor)
        // Written month date
        assertEquals("April 21, 2026", result.date)
    }

    // ── Stub 4: Blank receipt — nothing extracted ──────────────────────

    @Test
    fun `parse empty string returns all nulls`() {
        val result = ReceiptOcrScanner.parseReceiptText("")

        assertNull(result.total)
        assertNull(result.vendor)
        assertNull(result.date)
    }

    // ── Stub 5: Receipt with comma-decimal total ───────────────────────

    @Test
    fun `parse receipt with comma as decimal separator normalises to dot`() {
        val raw = """
            LIBRAIRIE RENAUD
            15/04/2026

            Livre              12,99
            Total              12,99
        """.trimIndent()

        val result = ReceiptOcrScanner.parseReceiptText(raw)

        // Comma should be normalised to period
        assertEquals("12.99", result.total)
    }
}
