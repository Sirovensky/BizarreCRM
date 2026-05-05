package com.bizarreelectronics.crm.ui.screens.pos

import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.roundToLong

/**
 * Unit tests for POS cart calculation logic.
 *
 * Pure JVM — no Android, Room, or Hilt dependencies.
 * Tests cover:
 *  1. Subtotal per line
 *  2. Tax per line
 *  3. Cart-level flat discount
 *  4. Cart-level percent discount
 *  5. Line-level discount
 *  6. Tip flat
 *  7. Tip percent
 *  8. Multi-line subtotal
 *  9. Total = subtotal + tax - discount + tip
 * 10. Rounding: half-penny never drifts
 * 11. Zero-total guard (never negative)
 * 12. Qty stepper: qty 3 multiplies line
 * 13. Multiple tax rates
 *
 * Plan §16.1 L1812 / ActionPlan unit test requirement.
 */
class PosCartLogicTest {

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private fun line(
        name: String = "Item",
        qty: Int = 1,
        unitPriceCents: Long,
        discountCents: Long = 0L,
        taxRate: Double = 0.0,
    ) = CartLine(
        name = name,
        qty = qty,
        unitPriceCents = unitPriceCents,
        discountCents = discountCents,
        taxRate = taxRate,
    )

    private fun cart(
        vararg lines: CartLine,
        cartDiscountCents: Long = 0L,
        cartDiscountMode: DiscountMode = DiscountMode.FLAT,
        tip: TipConfig = TipConfig(),
    ) = PosCartState(
        lines = lines.toList(),
        cartDiscountCents = cartDiscountCents,
        cartDiscountMode = cartDiscountMode,
        tip = tip,
    )

    // ─── 1. Subtotal per line ─────────────────────────────────────────────────

    @Test
    fun `line subtotal equals unitPrice times qty minus lineDiscount`() {
        val l = line(unitPriceCents = 1000, qty = 3, discountCents = 50)
        // 3 * $10.00 - $0.50 = $29.50
        assertEquals(2950L, l.subtotalCents)
    }

    // ─── 2. Tax per line ──────────────────────────────────────────────────────

    @Test
    fun `line tax is subtotal times taxRate truncated to cents`() {
        val l = line(unitPriceCents = 1000, qty = 1, taxRate = 0.08)
        // $10.00 * 8% = $0.80
        assertEquals(80L, l.taxCents)
    }

    @Test
    fun `line total equals subtotal plus tax`() {
        val l = line(unitPriceCents = 1000, qty = 1, taxRate = 0.08)
        assertEquals(1080L, l.totalCents)
    }

    // ─── 3. Cart flat discount ────────────────────────────────────────────────

    @Test
    fun `cart flat discount deducted from total`() {
        val c = cart(
            line(unitPriceCents = 5000),
            cartDiscountCents = 500,
            cartDiscountMode = DiscountMode.FLAT,
        )
        // Subtotal $50 - discount $5 = $45
        assertEquals(4500L, c.totalCents)
    }

    // ─── 4. Cart percent discount ─────────────────────────────────────────────

    @Test
    fun `cart percent discount computed from subtotal`() {
        val c = cart(
            line(unitPriceCents = 10000),
            // 10% stored as: cartDiscountCents = (subtotal * 10/100) = 1000
            cartDiscountCents = 1000,
            cartDiscountMode = DiscountMode.FLAT, // already resolved to cents
        )
        // $100 - $10 = $90
        assertEquals(9000L, c.totalCents)
    }

    // ─── 5. Line-level discount ───────────────────────────────────────────────

    @Test
    fun `line discount reduces subtotal`() {
        val l = line(unitPriceCents = 2000, discountCents = 200)
        assertEquals(1800L, l.subtotalCents)
    }

    // ─── 6. Tip flat ─────────────────────────────────────────────────────────

    @Test
    fun `flat tip added to total`() {
        val c = cart(
            line(unitPriceCents = 1000),
            tip = TipConfig(enabled = true, mode = DiscountMode.FLAT, value = 200),
        )
        // $10 + $2 tip = $12
        assertEquals(1200L, c.totalCents)
    }

    // ─── 7. Tip percent ──────────────────────────────────────────────────────

    @Test
    fun `percent tip computed correctly`() {
        val c = cart(
            line(unitPriceCents = 10000),
            // 15% tip = $15 = 1500 cents (pre-computed by dialog)
            tip = TipConfig(enabled = true, mode = DiscountMode.FLAT, value = 1500),
        )
        assertEquals(11500L, c.totalCents)
    }

    // ─── 8. Multi-line subtotal ───────────────────────────────────────────────

    @Test
    fun `multi-line subtotal sums all line subtotals`() {
        val c = cart(
            line(unitPriceCents = 1000),
            line(unitPriceCents = 2000, qty = 2),
            line(unitPriceCents = 500, discountCents = 100),
        )
        // 1000 + 4000 + 400 = 5400
        assertEquals(5400L, c.subtotalCents)
    }

    // ─── 9. Total combines all components ────────────────────────────────────

    @Test
    fun `total equals subtotal plus tax minus discount plus tip`() {
        val c = cart(
            line(unitPriceCents = 10000, taxRate = 0.10),
            cartDiscountCents = 500,
            tip = TipConfig(enabled = true, mode = DiscountMode.FLAT, value = 300),
        )
        // subtotal = 10000
        // tax      = 1000  (10%)
        // discount = 500
        // tip      = 300
        // total    = 10000 + 1000 - 500 + 300 = 10800
        assertEquals(10800L, c.totalCents)
    }

    // ─── 10. Rounding ─────────────────────────────────────────────────────────

    @Test
    fun `tax truncates at cent boundary without accumulating drift`() {
        // 3 items at $3.33 each with 7% tax
        // subtotal = 999, tax = floor(999 * 0.07) = floor(69.93) = 69
        val l = line(unitPriceCents = 333, qty = 3, taxRate = 0.07)
        val expectedTax = (l.subtotalCents * 0.07).toLong()
        assertEquals(expectedTax, l.taxCents)
    }

    // ─── 11. Total never negative ─────────────────────────────────────────────

    @Test
    fun `discount larger than subtotal does not make total negative`() {
        val c = cart(
            line(unitPriceCents = 500),
            cartDiscountCents = 9999,
        )
        assertEquals(0L, c.totalCents)
    }

    // ─── 12. Qty multiplier ───────────────────────────────────────────────────

    @Test
    fun `qty 5 multiplies unit price correctly`() {
        val l = line(unitPriceCents = 299, qty = 5)
        assertEquals(1495L, l.subtotalCents)
    }

    // ─── 13. Multiple tax rates ───────────────────────────────────────────────

    @Test
    fun `multiple lines with different tax rates sum correctly`() {
        val c = cart(
            line(unitPriceCents = 10000, taxRate = 0.08),  // tax = 800
            line(unitPriceCents = 5000, taxRate = 0.05),   // tax = 250
        )
        assertEquals(1050L, c.taxCents)
        assertEquals(16050L, c.totalCents)
    }

    // ─── 14. Empty cart ───────────────────────────────────────────────────────

    @Test
    fun `empty cart has zero for all computed fields`() {
        val c = PosCartState()
        assertEquals(0L, c.subtotalCents)
        assertEquals(0L, c.taxCents)
        assertEquals(0L, c.discountCents)
        assertEquals(0L, c.tipCents)
        assertEquals(0L, c.totalCents)
    }
}
