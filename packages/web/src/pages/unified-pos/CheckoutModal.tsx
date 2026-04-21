import { useState, useMemo, useEffect, useCallback, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { X, DollarSign, CreditCard, MoreHorizontal, Loader2, PenTool, Plus, Trash2, SplitSquareHorizontal, Crown, Sparkles } from 'lucide-react';
import toast from 'react-hot-toast';
import { posApi, membershipApi, settingsApi, blockchypApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { SignatureCanvas } from '@/components/shared/SignatureCanvas';
import { useUnifiedPosStore } from './store';
import { useDefaultTaxRate } from '@/hooks/useDefaultTaxRate';
import type { RepairCartItem, ProductCartItem, MiscCartItem } from './types';

// ─── Types ──────────────────────────────────────────────────────────

type PaymentMethod = 'Cash' | 'Card' | 'Other';

interface SplitPaymentEntry {
  method: PaymentMethod;
  amount: string;
}

const PAYMENT_METHODS: { key: PaymentMethod; label: string; icon: React.ElementType }[] = [
  { key: 'Cash', label: 'Cash', icon: DollarSign },
  { key: 'Card', label: 'Card', icon: CreditCard },
  { key: 'Other', label: 'Other', icon: MoreHorizontal },
];

// ─── Totals helper (same logic as LeftPanel) ────────────────────────

function useCheckoutTotals() {
  const { cartItems, discount, customer, memberDiscountApplied } = useUnifiedPosStore();
  const taxRate = useDefaultTaxRate();

  return useMemo(() => {
    let subtotal = 0;
    let taxableAmount = 0;

    for (const item of cartItems) {
      if (item.type === 'repair') {
        const labor = item.laborPrice - item.lineDiscount;
        subtotal += labor;
        if (item.taxable) taxableAmount += labor;
        for (const p of item.parts) {
          const partTotal = p.quantity * p.price;
          subtotal += partTotal;
          if (p.taxable) taxableAmount += partTotal;
        }
      } else if (item.type === 'product') {
        const lineTotal = item.quantity * item.unitPrice;
        subtotal += lineTotal;
        if (item.taxable && !item.taxInclusive) taxableAmount += lineTotal;
      } else {
        const lineTotal = item.quantity * item.unitPrice;
        subtotal += lineTotal;
        if (item.taxable) taxableAmount += lineTotal;
      }
    }

    let memberDiscount = 0;
    if (memberDiscountApplied && customer?.group_discount_pct && customer.group_discount_pct > 0) {
      if (customer.group_discount_type === 'fixed') {
        memberDiscount = customer.group_discount_pct;
      } else {
        memberDiscount = subtotal * (customer.group_discount_pct / 100);
      }
      memberDiscount = Math.round(memberDiscount * 100) / 100;
    }

    const discountAmount = discount + memberDiscount;
    const tax = Math.round(taxableAmount * taxRate * 100) / 100;
    const total = Math.max(0, Math.round((subtotal + tax - discountAmount) * 100) / 100);
    const itemCount = cartItems.length;

    return { itemCount, subtotal, discountAmount, tax, total };
  }, [cartItems, discount, customer, memberDiscountApplied, taxRate]);
}

// ─── Build checkout payload ─────────────────────────────────────────

function buildPayload(
  store: ReturnType<typeof useUnifiedPosStore.getState>,
  paymentMethod: PaymentMethod,
  paymentAmount: number,
  splitPaymentsArg?: SplitPaymentEntry[],
) {
  const { cartItems, customer, discount, discountReason, meta, sourceTicketId } = store;

  const repairs = cartItems.filter((i): i is RepairCartItem => i.type === 'repair');
  const products = cartItems.filter((i): i is ProductCartItem => i.type === 'product');
  const miscItems = cartItems.filter((i): i is MiscCartItem => i.type === 'misc');

  const devices = repairs.map((r) => ({
    device_type: r.device.device_type,
    device_name: r.device.device_name,
    device_model_id: r.device.device_model_id,
    imei: r.device.imei,
    serial: r.device.serial,
    security_code: r.device.security_code,
    color: r.device.color,
    network: r.device.network,
    pre_conditions: r.device.pre_conditions,
    additional_notes: r.device.additional_notes,
    device_location: r.device.device_location,
    warranty: r.device.warranty,
    warranty_days: r.device.warranty_days,
    service_name: r.serviceName,
    repair_service_id: r.repairServiceId,
    selected_grade_id: r.selectedGradeId,
    labor_price: r.laborPrice,
    line_discount: r.lineDiscount,
    parts: r.parts,
    taxable: r.taxable,
  }));

  const productItems = products.map((p) => ({
    inventory_item_id: p.inventoryItemId,
    name: p.name,
    sku: p.sku,
    quantity: p.quantity,
    unit_price: p.unitPrice,
    taxable: p.taxable,
    tax_inclusive: p.taxInclusive,
  }));

  const misc = miscItems.map((m) => ({
    name: m.name,
    unit_price: m.unitPrice,
    quantity: m.quantity,
    taxable: m.taxable,
  }));

  // Build split payments array for backend if in split mode
  const payments = splitPaymentsArg && splitPaymentsArg.length > 0
    ? splitPaymentsArg.map((sp) => ({ method: sp.method, amount: parseFloat(sp.amount) || 0 }))
    : undefined;

  return {
    mode: 'checkout' as const,
    customer_id: customer?.id ?? null,
    existing_ticket_id: sourceTicketId ?? null,
    ticket: {
      devices,
      source: meta.source,
      assigned_to: meta.assignedTo,
      discount,
      discount_reason: discountReason,
      internal_notes: meta.internalNotes,
      labels: meta.labels,
      due_date: meta.dueDate,
    },
    product_items: productItems,
    misc_items: misc,
    payment_method: paymentMethod,
    payment_amount: paymentAmount,
    payments,
  };
}

// ─── CheckoutModal ──────────────────────────────────────────────────

interface CheckoutModalProps {
  onClose: () => void;
}

export function CheckoutModal({ onClose }: CheckoutModalProps) {
  const store = useUnifiedPosStore;
  const { setShowSuccess, meta, setMeta } = useUnifiedPosStore();
  const totals = useCheckoutTotals();

  const [method, setMethod] = useState<PaymentMethod>('Cash');
  const [cashGiven, setCashGiven] = useState('');
  const [processing, setProcessing] = useState(false);
  const [signature, setSignature] = useState('');
  const [showSignature, setShowSignature] = useState(false);
  const [splitMode, setSplitMode] = useState(false);
  const [splitPayments, setSplitPayments] = useState<SplitPaymentEntry[]>([
    { method: 'Cash', amount: '' },
    { method: 'Card', amount: '' },
  ]);

  const splitTotal = useMemo(
    () => Math.round(
      splitPayments.reduce((sum, sp) => sum + (Math.round((parseFloat(sp.amount) || 0) * 100)), 0)
    ) / 100,
    [splitPayments],
  );
  const splitRemaining = Math.max(0, Math.round((totals.total - splitTotal) * 100) / 100);

  const handleSignatureSave = useCallback((dataUrl: string) => {
    setSignature(dataUrl);
  }, []);

  // ─── BlockChyp terminal status ──────────────────────────────────
  // AUDIT-WEB-003: gate card payments behind a real terminal. If BlockChyp
  // is not configured, the Card button is disabled — no simulation fallback.
  const { data: bcStatusData } = useQuery({
    queryKey: ['blockchyp-status'],
    queryFn: () => blockchypApi.status(),
    staleTime: 30_000,
  });
  const blockchypConfigured = bcStatusData?.data?.data?.enabled ?? false;

  // ─── Membership Upsell ──────────────────────────────────────────
  const { customer } = useUnifiedPosStore();
  const queryClient = useQueryClient();

  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string>;
    },
    staleTime: 60_000,
  });
  const membershipEnabled = configData?.['membership_enabled'] === 'true';

  const { data: memberStatus } = useQuery({
    queryKey: ['membership', 'customer', customer?.id],
    queryFn: async () => {
      const res = await membershipApi.getCustomerMembership(customer!.id);
      return res.data.data as { id: number; status: string; tier_name: string; discount_pct: number } | null;
    },
    enabled: membershipEnabled && !!customer?.id,
    staleTime: 30_000,
  });

  const { data: tiersForUpsell } = useQuery({
    queryKey: ['membership', 'tiers'],
    queryFn: async () => {
      const res = await membershipApi.getTiers();
      return res.data.data as Array<{
        id: number; name: string; monthly_price: number; discount_pct: number;
        discount_applies_to: string; color: string;
      }>;
    },
    enabled: membershipEnabled && !!customer?.id && !memberStatus,
    staleTime: 60_000,
  });

  const bestTier = useMemo(() => {
    if (!tiersForUpsell || tiersForUpsell.length === 0) return null;
    // Pick the tier with the highest discount
    return [...tiersForUpsell].sort((a, b) => b.discount_pct - a.discount_pct)[0];
  }, [tiersForUpsell]);

  const [enrollingTier, setEnrollingTier] = useState<number | null>(null);

  const upsellSubscribeMut = useMutation({
    mutationFn: (tierId: number) =>
      membershipApi.subscribe({ customer_id: customer!.id, tier_id: tierId }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['membership', 'customer', customer?.id] });
      queryClient.invalidateQueries({ queryKey: ['membership', 'subscriptions'] });
      setEnrollingTier(null);
      toast.success('Membership activated! Discount will apply to future orders.');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Signup failed'),
  });

  const showUpsell = membershipEnabled && !!customer?.id && !memberStatus && !!bestTier;

  // D4-6: focus trap + ESC — keyboard-only techs must not tab out of the modal
  // into invisible elements behind the overlay. Tab / Shift+Tab cycle inside
  // the dialog; Escape closes (unless a card transaction is processing).
  const dialogRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    // Move focus to first focusable element on open.
    const node = dialogRef.current;
    if (node) {
      const focusables = node.querySelectorAll<HTMLElement>(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      );
      focusables[0]?.focus();
    }
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !processing) {
        onClose();
        return;
      }
      if (e.key === 'Tab' && node) {
        const focusables = Array.from(
          node.querySelectorAll<HTMLElement>(
            'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
          ),
        ).filter((el) => !el.hasAttribute('disabled'));
        if (focusables.length === 0) return;
        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [onClose, processing]);

  const cashAmount = parseFloat(cashGiven) || 0;
  const change = Math.max(0, Math.round((cashAmount - totals.total) * 100) / 100);

  // Quick cash buttons: exact, round up to $5, $10, $20
  const quickAmounts = useMemo(() => {
    const exact = totals.total;
    const amounts = [exact];
    const roundTo = (n: number, step: number) => Math.ceil(n / step) * step;
    const r5 = roundTo(exact, 5);
    const r10 = roundTo(exact, 10);
    const r20 = roundTo(exact, 20);
    if (r5 > exact) amounts.push(r5);
    if (r10 > r5) amounts.push(r10);
    if (r20 > r10) amounts.push(r20);
    return amounts;
  }, [totals.total]);

  const handleCompleteCheckout = async () => {
    if (splitMode) {
      if (splitTotal < totals.total) {
        toast.error(`Split payments total ($${splitTotal.toFixed(2)}) must cover the total ($${totals.total.toFixed(2)})`);
        return;
      }
      const validEntries = splitPayments.filter((sp) => parseFloat(sp.amount) > 0);
      if (validEntries.length < 2) {
        toast.error('Add at least two payment methods for split payment');
        return;
      }
    } else if (method === 'Cash' && cashAmount < totals.total) {
      toast.error('Cash amount must be at least the total');
      return;
    }

    setProcessing(true);
    try {
      const validSplits = splitMode
        ? splitPayments.filter((sp) => parseFloat(sp.amount) > 0)
        : undefined;
      const payload = buildPayload(
        store.getState(),
        method,
        splitMode ? splitTotal : (method === 'Cash' ? cashAmount : totals.total),
        validSplits,
      );
      const res = await posApi.checkoutWithTicket(payload);

      // For Card payments, run the terminal charge against the newly-created
      // invoice. The checkout creates the invoice record first; BlockChyp then
      // captures the card. On terminal failure we still show the success screen
      // (invoice is created) and surface a warning so the cashier can retry
      // the charge from the invoice detail page.
      if (!splitMode && method === 'Card' && blockchypConfigured) {
        const invoiceId: number | undefined = res.data?.data?.invoice?.id;
        if (invoiceId) {
          try {
            const terminalRes = await blockchypApi.processPayment(invoiceId);
            const terminalResult = terminalRes.data?.data;
            if (!terminalResult?.success) {
              toast.error(
                `Invoice created but terminal declined: ${terminalResult?.error || terminalResult?.responseDescription || 'Payment declined'}. Retry from the invoice page.`,
                { duration: 8000 },
              );
            }
          } catch (terminalErr: unknown) {
            const msg = terminalErr instanceof Error ? terminalErr.message : 'Terminal error';
            toast.error(`Invoice created but terminal charge failed: ${msg}. Retry from the invoice page.`, { duration: 8000 });
          }
        }
      }

      setShowSuccess({ ...res.data.data, mode: 'checkout' });
      // Advance the checkout tutorial when payment is completed.
      window.dispatchEvent(new CustomEvent('pos:payment-completed'));
      onClose();
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message
        || (err instanceof Error ? err.message : 'Checkout failed');
      toast.error(msg);
    } finally {
      setProcessing(false);
    }
  };

  const canComplete = !processing && (splitMode
    ? splitTotal >= totals.total
    : method === 'Cash' ? cashAmount >= totals.total : true);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" role="dialog" aria-modal="true" aria-labelledby="checkout-title">
      <div ref={dialogRef} className="relative w-full max-w-lg rounded-xl bg-white shadow-2xl dark:bg-surface-900">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-surface-200 px-6 py-4 dark:border-surface-700">
          <h2 id="checkout-title" className="text-lg font-semibold text-surface-900 dark:text-surface-50">Checkout</h2>
          <button aria-label="Close" onClick={onClose} className="rounded-lg p-1 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="px-6 py-4 space-y-5">
          {/* Order Summary */}
          <div className="space-y-1.5 rounded-lg bg-surface-50 p-4 dark:bg-surface-800">
            <div className="flex justify-between text-sm text-surface-600 dark:text-surface-300">
              <span>{totals.itemCount} item{totals.itemCount !== 1 ? 's' : ''}</span>
              <span>Subtotal: ${totals.subtotal.toFixed(2)}</span>
            </div>
            {totals.discountAmount > 0 && (
              <div className="flex justify-between text-sm text-green-600 dark:text-green-400">
                <span>Discount</span>
                <span>-${totals.discountAmount.toFixed(2)}</span>
              </div>
            )}
            <div className="flex justify-between text-sm text-surface-600 dark:text-surface-300">
              <span>Tax</span>
              <span>${totals.tax.toFixed(2)}</span>
            </div>
            <div className="flex justify-between border-t border-surface-200 pt-1.5 text-base font-bold text-surface-900 dark:border-surface-600 dark:text-surface-50">
              <span>Total</span>
              <span>${totals.total.toFixed(2)}</span>
            </div>
          </div>

          {/* Membership Upsell Banner */}
          {showUpsell && bestTier && (
            <div
              className="rounded-lg border-2 p-3"
              style={{ borderColor: bestTier.color, backgroundColor: bestTier.color + '0D' }}
            >
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-2 min-w-0">
                  <Sparkles className="h-5 w-5 shrink-0" style={{ color: bestTier.color }} />
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-surface-900 dark:text-surface-100 truncate">
                      Save {bestTier.discount_pct}% with {bestTier.name}!
                    </p>
                    <p className="text-xs text-surface-500 truncate">
                      ${bestTier.monthly_price.toFixed(2)}/mo &mdash; {bestTier.discount_pct}% off {bestTier.discount_applies_to}
                    </p>
                  </div>
                </div>
                <button
                  onClick={() => {
                    setEnrollingTier(bestTier.id);
                    upsellSubscribeMut.mutate(bestTier.id);
                  }}
                  disabled={upsellSubscribeMut.isPending}
                  className="shrink-0 inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:opacity-90"
                  style={{ backgroundColor: bestTier.color }}
                >
                  {upsellSubscribeMut.isPending
                    ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    : <Crown className="h-3.5 w-3.5" />}
                  Sign Up
                </button>
              </div>
            </div>
          )}

          {/* Internal Notes */}
          <div>
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">
              Internal Notes
            </label>
            <textarea
              data-tutorial-target="checkout:internal-note-textarea"
              value={meta.internalNotes}
              onChange={(e) => setMeta({ internalNotes: e.target.value })}
              placeholder="e.g. Replaced digitizer, tested touch, full charge cycle done"
              rows={2}
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-teal-500 resize-none"
            />
          </div>

          {/* Payment Method */}
          <div>
            <div className="mb-2 flex items-center justify-between">
              <p className="text-sm font-medium text-surface-700 dark:text-surface-300">Payment Method</p>
              <button
                onClick={() => setSplitMode(!splitMode)}
                className={cn(
                  'flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium transition-colors',
                  splitMode
                    ? 'bg-teal-100 text-teal-700 dark:bg-teal-500/20 dark:text-teal-400'
                    : 'text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200',
                )}
              >
                <SplitSquareHorizontal className="h-3.5 w-3.5" />
                Split Payment
              </button>
            </div>

            {!splitMode && (
              <div className="grid grid-cols-4 gap-2">
                {PAYMENT_METHODS.map(({ key, label, icon: Icon }) => {
                  // AUDIT-WEB-003: Card is only available when a BlockChyp terminal
                  // is configured. No simulation fallback.
                  const isCardDisabled = key === 'Card' && !blockchypConfigured;
                  return (
                    <button
                      key={key}
                      disabled={isCardDisabled}
                      title={isCardDisabled ? 'Terminal not configured — go to Settings → Payments to pair a BlockChyp terminal' : undefined}
                      onClick={() => { if (!isCardDisabled) { setMethod(key); setProcessing(false); } }}
                      className={cn(
                        'flex flex-col items-center gap-1 rounded-lg border p-3 text-xs font-medium transition-colors',
                        isCardDisabled
                          ? 'cursor-not-allowed border-surface-200 opacity-50 dark:border-surface-700'
                          : method === key
                            ? 'border-teal-500 bg-teal-50 text-teal-700 dark:border-teal-400 dark:bg-teal-500/10 dark:text-teal-400'
                            : 'border-surface-200 text-surface-600 hover:border-surface-300 dark:border-surface-700 dark:text-surface-400',
                      )}
                    >
                      <Icon className="h-5 w-5" />
                      {label}
                    </button>
                  );
                })}
              </div>
            )}

            {/* Split Payment UI */}
            {splitMode && (
              <div className="space-y-2">
                {splitPayments.map((sp, idx) => (
                  <div key={idx} className="flex items-center gap-2">
                    <select
                      value={sp.method}
                      onChange={(e) => {
                        const updated = splitPayments.map((p, i) =>
                          i === idx ? { ...p, method: e.target.value as PaymentMethod } : p,
                        );
                        setSplitPayments(updated);
                      }}
                      className="flex-shrink-0 rounded-lg border border-surface-300 bg-white px-2 py-2 text-sm dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
                    >
                      {PAYMENT_METHODS.map(({ key, label }) => (
                        <option key={key} value={key}>{label}</option>
                      ))}
                    </select>
                    <div className="relative flex-1">
                      <span className="absolute left-2 top-1/2 -translate-y-1/2 text-surface-400 text-sm">$</span>
                      <input
                        type="text" inputMode="decimal" pattern="[0-9.]*"
                        step="0.01"
                        min="0"
                        value={sp.amount}
                        onChange={(e) => {
                          const updated = splitPayments.map((p, i) =>
                            i === idx ? { ...p, amount: e.target.value } : p,
                          );
                          setSplitPayments(updated);
                        }}
                        placeholder="0.00"
                        className="w-full rounded-lg border border-surface-300 bg-white py-2 pl-6 pr-2 text-sm font-medium focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
                      />
                    </div>
                    {splitPayments.length > 2 && (
                      <button
                        onClick={() => setSplitPayments(splitPayments.filter((_, i) => i !== idx))}
                        className="rounded p-1 text-surface-400 hover:text-red-500"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    )}
                  </div>
                ))}
                <div className="flex items-center justify-between">
                  <button
                    onClick={() => setSplitPayments([...splitPayments, { method: 'Cash', amount: '' }])}
                    className="flex items-center gap-1 text-xs font-medium text-teal-600 hover:text-teal-700 dark:text-teal-400"
                  >
                    <Plus className="h-3.5 w-3.5" /> Add Method
                  </button>
                  {splitRemaining > 0 ? (
                    <span className="text-xs font-medium text-amber-600 dark:text-amber-400">
                      Remaining: ${splitRemaining.toFixed(2)}
                    </span>
                  ) : (
                    <span className="text-xs font-medium text-green-600 dark:text-green-400">
                      Fully covered
                    </span>
                  )}
                </div>
              </div>
            )}
          </div>

          {/* Cash-specific UI */}
          {!splitMode && method === 'Cash' && (
            <div className="space-y-3">
              <div>
                <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">
                  Amount Given
                </label>
                <input
                  type="text" inputMode="decimal" pattern="[0-9.]*"
                  step="0.01"
                  min="0"
                  value={cashGiven}
                  onChange={(e) => setCashGiven(e.target.value)}
                  className="w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-lg font-semibold focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
                  placeholder="0.00"
                  autoFocus
                />
              </div>
              <div className="flex flex-wrap gap-2">
                {quickAmounts.map((amt) => (
                  <button
                    key={amt}
                    type="button"
                    onMouseDown={(e) => { e.preventDefault(); setCashGiven(amt.toFixed(2)); }}
                    className="rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-300 dark:hover:bg-surface-700"
                  >
                    ${amt.toFixed(2)}
                  </button>
                ))}
              </div>
              {cashAmount >= totals.total && (
                <div className="rounded-lg bg-green-50 px-4 py-2 text-center text-lg font-bold text-green-700 dark:bg-green-500/10 dark:text-green-400">
                  Change: ${change.toFixed(2)}
                </div>
              )}
            </div>
          )}

          {/* Card processing — AUDIT-WEB-003: BlockChyp terminal charge fires
              during handleCompleteCheckout after the invoice is created. */}
          {!splitMode && method === 'Card' && blockchypConfigured && (
            <div className="rounded-lg bg-teal-50 px-4 py-3 text-center dark:bg-teal-500/10">
              <p className="text-sm font-medium text-teal-700 dark:text-teal-300">
                Card will be charged on the terminal when you click "Complete Checkout".
              </p>
            </div>
          )}
        </div>

        {/* Signature */}
        <div className="border-t border-surface-200 px-6 py-3 dark:border-surface-700">
          <button
            onClick={() => setShowSignature(!showSignature)}
            className="inline-flex items-center gap-1.5 text-xs font-medium text-surface-500 hover:text-surface-700 dark:hover:text-surface-300"
          >
            <PenTool className="h-3.5 w-3.5" />
            {signature ? 'Signature captured' : 'Add customer signature (optional)'}
          </button>
          {showSignature && (
            <div className="mt-2">
              <SignatureCanvas onSave={handleSignatureSave} width={440} height={120} />
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="border-t border-surface-200 px-6 py-4 dark:border-surface-700">
          <button
            data-tutorial-target="checkout:complete-payment-button"
            onClick={handleCompleteCheckout}
            disabled={!canComplete}
            className={cn(
              'w-full rounded-lg py-3 text-sm font-semibold transition-colors',
              canComplete
                ? 'bg-teal-600 text-white hover:bg-teal-700'
                : 'cursor-not-allowed bg-surface-200 text-surface-400 dark:bg-surface-700 dark:text-surface-500',
            )}
          >
            Complete Checkout
          </button>
        </div>
      </div>
    </div>
  );
}
