/**
 * WEB-FH-005 (Fixer-O 2026-04-24): cents-pure totals helper shared by
 * `LeftPanel.useTotals` and `CheckoutModal.useCheckoutTotals`. Both panels
 * previously did the same float-discount-tax math with `Math.round(x*100)/100`
 * chains, which can drift 1¢ across re-multiplications (the classic
 * 0.1+0.2=0.30000000000000004 trap) and disagree with the server's cents-int
 * recompute (POS-SALES-001).
 *
 * Strategy: convert every line into integer cents up front, do all arithmetic
 * in cents, and only divide by 100 once for display. The pro-rata discount
 * allocation that WEB-FH-006 added survives unchanged — we just do it on
 * integers so the rounding boundary is well-defined.
 *
 * Inputs are still floats (dollars) because the cart store types are dollars
 * everywhere; we round to cents at the boundary.
 */

import type { CartItem, CustomerResult } from './types';

export interface PosTotals {
  itemCount: number;
  /** Pre-discount subtotal, in dollars (rounded to cents). */
  subtotal: number;
  /** Total discount applied (manual + member), in dollars. */
  discountAmount: number;
  /** Sales tax on the post-discount taxable base, in dollars. */
  tax: number;
  /** subtotal + tax − discount, clamped at 0, in dollars. */
  total: number;
  /**
   * Authoritative integer-cents total (WEB-FB-009 / WEB-FH-014 / Fixer-V).
   * Use this for comparisons like split-payment "covers total" checks where
   * a 1¢ float drift would block a legitimately-funded sale or pass an
   * underpayment. Display fields stay as dollars.
   */
  totalCents: number;
}

/** Round a dollar float to integer cents. Single-source rounding. */
const toCents = (dollars: number): number => Math.round(dollars * 100);
const fromCents = (cents: number): number => cents / 100;

export function computePosTotals(args: {
  cartItems: CartItem[];
  discount: number;
  customer: CustomerResult | null;
  memberDiscountApplied: boolean;
  taxRate: number;
}): PosTotals {
  const { cartItems, discount, customer, memberDiscountApplied, taxRate } = args;

  let subtotalC = 0;
  let taxableC = 0;

  for (const item of cartItems) {
    if (item.type === 'repair') {
      const laborC = toCents(item.laborPrice) - toCents(item.lineDiscount);
      subtotalC += laborC;
      if (item.taxable) taxableC += laborC;
      for (const p of item.parts) {
        const partC = toCents(p.quantity * p.price);
        subtotalC += partC;
        if (p.taxable) taxableC += partC;
      }
    } else if (item.type === 'product') {
      const lineC = toCents(item.quantity * item.unitPrice);
      subtotalC += lineC;
      if (item.taxable && !item.taxInclusive) taxableC += lineC;
    } else {
      // misc
      const lineC = toCents(item.quantity * item.unitPrice);
      subtotalC += lineC;
      if (item.taxable) taxableC += lineC;
    }
  }

  // Member discount, rounded to cents at the boundary.
  let memberDiscountC = 0;
  if (memberDiscountApplied && customer?.group_discount_pct && customer.group_discount_pct > 0) {
    if (customer.group_discount_type === 'fixed') {
      memberDiscountC = toCents(customer.group_discount_pct);
    } else {
      memberDiscountC = Math.round(subtotalC * (customer.group_discount_pct / 100));
    }
  }

  const discountC = toCents(discount) + memberDiscountC;

  // WEB-FH-006 pro-rata discount allocation, on integers. Tax base is the
  // taxable lines minus their share of the discount. Round once at the end.
  const taxableShareC =
    subtotalC > 0 ? Math.round(discountC * (taxableC / subtotalC)) : 0;
  const netTaxableC = Math.max(0, taxableC - taxableShareC);
  const taxC = Math.round(netTaxableC * taxRate);
  const totalC = Math.max(0, subtotalC + taxC - discountC);

  return {
    itemCount: cartItems.length,
    subtotal: fromCents(subtotalC),
    discountAmount: fromCents(discountC),
    tax: fromCents(taxC),
    total: fromCents(totalC),
    totalCents: totalC,
  };
}
