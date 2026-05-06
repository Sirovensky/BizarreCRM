import { useState, useMemo, useEffect, useCallback, useRef } from 'react';
import { Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { X, DollarSign, CreditCard, MoreHorizontal, Loader2, PenTool, Plus, Trash2, SplitSquareHorizontal, Crown, Sparkles, AlertTriangle } from 'lucide-react';
import toast from 'react-hot-toast';
import { posApi, membershipApi, settingsApi, blockchypApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { SignatureCanvas } from '@/components/shared/SignatureCanvas';
import { useUnifiedPosStore } from './store';
import { useDefaultTaxRate } from '@/hooks/useDefaultTaxRate';
import { computePosTotals } from './totals';
import { formatCurrency } from '@/utils/format';
import type { RepairCartItem, ProductCartItem, MiscCartItem } from './types';
import { submitTrainingTransaction, useIsTraining } from './TrainingModeBanner';
import { safeHexColor } from '@/utils/safeColor';

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

const DEFAULT_TIER_COLOR = '#0f766e';

function getOpaqueHexColor(color: string | undefined | null): string {
  const safe = safeHexColor(color, DEFAULT_TIER_COLOR);
  const hex = safe.slice(1);

  if (hex.length === 3 || hex.length === 4) {
    const r = hex.charAt(0);
    const g = hex.charAt(1);
    const b = hex.charAt(2);
    return `#${r}${r}${g}${g}${b}${b}`;
  }

  if (hex.length === 8) {
    return `#${hex.slice(0, 6)}`;
  }

  return safe;
}

function getRelativeLuminance(hexColor: string): number {
  const hex = getOpaqueHexColor(hexColor).slice(1);
  const channel = (pair: string) => {
    const value = parseInt(pair, 16) / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  };
  const r = channel(hex.slice(0, 2));
  const g = channel(hex.slice(2, 4));
  const b = channel(hex.slice(4, 6));

  return (0.2126 * r) + (0.7152 * g) + (0.0722 * b);
}

function getReadableTextColor(backgroundColor: string): '#000000' | '#ffffff' {
  const luminance = getRelativeLuminance(backgroundColor);
  const whiteContrast = 1.05 / (luminance + 0.05);
  const blackContrast = (luminance + 0.05) / 0.05;

  return blackContrast >= whiteContrast ? '#000000' : '#ffffff';
}

// ─── Totals helper (shared cents-int helper) ────────────────────────
// WEB-FH-005 (Fixer-O 2026-04-24): moved to `./totals.ts`. LeftPanel and
// this modal now share one cents-pure implementation, eliminating the 1¢
// drift between cart display, modal display, and the server recompute.

function useCheckoutTotals() {
  const { cartItems, discount, customer, memberDiscountApplied } = useUnifiedPosStore();
  const taxRate = useDefaultTaxRate();
  return useMemo(
    () => computePosTotals({ cartItems, discount, customer, memberDiscountApplied, taxRate }),
    [cartItems, discount, customer, memberDiscountApplied, taxRate],
  );
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
    due_on: r.device.due_date ?? null,
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
      referral_source: meta.referralSource || undefined,
      assigned_to: meta.assignedTo,
      discount,
      discount_reason: discountReason,
      internal_notes: meta.internalNotes,
      labels: meta.labels,
      due_date: meta.dueDate,
      signature_data_url: undefined as string | undefined,
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
  const isTraining = useIsTraining();

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
  const [terminalError, setTerminalError] = useState<string | null>(null);
  const [terminalErrorInvoiceId, setTerminalErrorInvoiceId] = useState<number | null>(null);

  // WEB-FB-009 / WEB-FH-014 (Fixer-V 2026-04-25): keep the split-payment
  // running tally in integer cents and only divide once for display. The
  // previous code summed cents then divided by 100, which when compared to
  // `totals.total` (also a float) could fail at the 1¢ boundary — e.g. three
  // 33.33 splits looked like "99.99 < 100" and blocked a legitimate even-split
  // checkout, or worse, passed a sale a cent short. The cents-int comparison
  // matches the server's cents-pure recompute (POS-SALES-001).
  const splitTotalCents = useMemo(
    () =>
      splitPayments.reduce(
        (sum, sp) => sum + Math.round((parseFloat(sp.amount) || 0) * 100),
        0,
      ),
    [splitPayments],
  );
  const splitTotal = splitTotalCents / 100;
  const splitRemainingCents = Math.max(0, totals.totalCents - splitTotalCents);
  const splitRemaining = splitRemainingCents / 100;
  const splitCoversTotal = splitTotalCents >= totals.totalCents;

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
  const requireReferral = configData?.['pos_require_referral'] === '1' || configData?.['pos_require_referral'] === 'true';

  const { data: referralSourcesData } = useQuery({
    queryKey: ['settings', 'referral-sources'],
    queryFn: () => settingsApi.getReferralSources(),
    enabled: requireReferral,
    staleTime: 60_000,
  });
  const referralSources: Array<{ id: number; name: string }> =
    referralSourcesData?.data?.data?.referral_sources || referralSourcesData?.data?.data || [];

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
  const bestTierColor = getOpaqueHexColor(bestTier?.color);
  const bestTierTextColor = getReadableTextColor(bestTierColor);

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
      // WEB-FB-009 / WEB-FH-014: cents-int compare. Float compare drifted by
      // 1¢ on three-way even splits (33.33×3) and either blocked legit
      // checkouts or let a one-cent underpayment through.
      if (!splitCoversTotal) {
        // @audit-fixed (WEB-FF-003 / Fixer-PP 2026-04-25): tenant-aware currency.
        toast.error(`Split payments total (${formatCurrency(splitTotal)}) must cover the total (${formatCurrency(totals.total)})`);
        return;
      }
      const validEntries = splitPayments.filter((sp) => parseFloat(sp.amount) > 0);
      if (validEntries.length < 2) {
        toast.error('Add at least two payment methods for split payment');
        return;
      }
      if (validEntries.some((sp) => sp.method === 'Card') && !blockchypConfigured) {
        toast.error('Pair a BlockChyp terminal before accepting card split payments');
        return;
      }
    } else if (method === 'Card' && !blockchypConfigured) {
      toast.error('Pair a BlockChyp terminal before accepting card payments');
      return;
    } else if (method === 'Cash' && cashAmount < totals.total) {
      toast.error('Cash amount must be at least the total');
      return;
    }
    const hasRepair = store.getState().cartItems.some((item) => item.type === 'repair');
    if (requireReferral && hasRepair && !store.getState().meta.referralSource) {
      toast.error('Select a referral source');
      return;
    }

    setProcessing(true);
    try {
      const validSplits = splitMode
        ? splitPayments.filter((sp) => parseFloat(sp.amount) > 0)
        : undefined;
      const cardSplits = validSplits?.filter((sp) => sp.method === 'Card') ?? [];
      const checkoutSplits = validSplits?.filter((sp) => sp.method !== 'Card');
      const checkoutSplitTotal = checkoutSplits?.reduce(
        (sum, sp) => sum + (parseFloat(sp.amount) || 0),
        0,
      ) ?? 0;
      const initialPaymentAmount = splitMode
        ? checkoutSplitTotal
        : (method === 'Card' ? 0 : method === 'Cash' ? cashAmount : totals.total);
      const payload = buildPayload(
        store.getState(),
        method,
        initialPaymentAmount,
        checkoutSplits && checkoutSplits.length > 0 ? checkoutSplits : undefined,
      );
      if (signature) {
        payload.ticket.signature_data_url = signature;
      }

      if (isTraining) {
        await submitTrainingTransaction({
          cart: payload,
          total_cents: totals.totalCents,
          kind: 'checkout',
        });
        await queryClient.invalidateQueries({ queryKey: ['onboarding-state'] });
        await queryClient.invalidateQueries({ queryKey: ['onboarding', 'state'] });
        setShowSuccess({
          mode: 'checkout',
          ticket: null,
          invoice: {
            id: 0,
            order_id: 'TRAINING',
            total: totals.total,
          },
          total: totals.total,
          change: method === 'Cash' ? Math.max(0, cashAmount - totals.total) : 0,
          customer_name: 'Training session',
        });
        window.dispatchEvent(new CustomEvent('pos:payment-completed'));
        onClose();
        return;
      }

      // WEB-FH-001 / WEB-FH-002: stable idempotency key for this cart-session.
      // Reused on every retry of the SAME submit so a double-click or flaky
      // network can't double-charge — server idempotent middleware caches by
      // (user, url, key) for 5 minutes.
      const idempotencyKey = store.getState().ensureIdempotencyKey();
      const res = await posApi.checkoutWithTicket(payload, idempotencyKey);

      // For Card payments, run the terminal charge against the newly-created
      // invoice. The checkout creates the invoice record first; BlockChyp then
      // captures the card. On terminal failure we still need the success
      // screen (invoice is created and must be reachable for retry) but
      // WEB-FH-008: track the decline so the screen renders a RED warning
      // instead of the green "Payment Received!" — a toast under fluorescent
      // POS lights is too easy to miss, and the cashier was handing receipts
      // to customers whose card had actually declined.
      let cardDeclined = false;
      let cardDeclineMessage: string | null = null;

      if (blockchypConfigured) {
        const invoiceId: number | undefined = res.data?.data?.invoice?.id;
        if (invoiceId) {
          if (!splitMode && method === 'Card') {
            // Single Card payment — charge the invoice balance after the
            // server creates it unpaid; BlockChyp records the payment row only
            // after authorization metadata exists.
            try {
              const terminalRes = await blockchypApi.processPayment(invoiceId);
              const terminalResult = terminalRes.data?.data;
              if (!terminalResult?.success) {
                cardDeclined = true;
                cardDeclineMessage =
                  terminalResult?.error || terminalResult?.responseDescription || 'Payment declined';
                setTerminalError(`Invoice created but terminal declined: ${cardDeclineMessage}.`);
                setTerminalErrorInvoiceId(invoiceId);
              }
            } catch (terminalErr: unknown) {
              cardDeclined = true;
              cardDeclineMessage = terminalErr instanceof Error ? terminalErr.message : 'Terminal error';
              setTerminalError(`Invoice created but terminal charge failed: ${cardDeclineMessage}.`);
              setTerminalErrorInvoiceId(invoiceId);
            }
          } else if (splitMode) {
            // WEB-W3-004: split payments — each Card leg must fire an independent
            // BlockChyp `charge` for that leg's amount. Non-card legs (Cash/Other)
            // are already recorded by the POS checkout endpoint; we only hit
            // the terminal for Card legs.
            const legErrors: string[] = [];
            for (const leg of cardSplits) {
              const legAmount = parseFloat(leg.amount) || 0;
              if (legAmount <= 0) continue;
              try {
                const terminalRes = await blockchypApi.processPayment(invoiceId, undefined, legAmount);
                const terminalResult = terminalRes.data?.data;
                if (!terminalResult?.success) {
                  cardDeclined = true;
                  const legMsg =
                    terminalResult?.error || terminalResult?.responseDescription || 'Payment declined';
                  cardDeclineMessage = cardDeclineMessage
                    ? `${cardDeclineMessage}; ${legMsg}`
                    : legMsg;
                  legErrors.push(`Card leg ${formatCurrency(legAmount)} declined: ${legMsg}.`);
                }
              } catch (terminalErr: unknown) {
                cardDeclined = true;
                const legMsg = terminalErr instanceof Error ? terminalErr.message : 'Terminal error';
                cardDeclineMessage = cardDeclineMessage
                  ? `${cardDeclineMessage}; ${legMsg}`
                  : legMsg;
                legErrors.push(`Card leg ${formatCurrency(legAmount)} failed: ${legMsg}.`);
              }
            }
            if (legErrors.length > 0) {
              setTerminalError(legErrors.join(' '));
              setTerminalErrorInvoiceId(invoiceId);
            }
          }
        }
      }

      // WEB-UIUX-222: terminal failures stay in the modal as a persistent inline
      // error — do NOT close or show the success screen until the user dismisses
      // and retries from the invoice page.
      if (cardDeclined) {
        return;
      }

      setShowSuccess({
        ...res.data.data,
        mode: 'checkout',
      });
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
    ? splitCoversTotal
    : method === 'Cash' ? cashAmount >= totals.total : true);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" role="dialog" aria-modal="true" aria-labelledby="checkout-title">
      <div ref={dialogRef} className="relative w-full max-w-lg rounded-xl bg-white shadow-2xl dark:bg-surface-900">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-surface-200 px-6 py-4 dark:border-surface-700">
          <h2 id="checkout-title" className="text-lg font-semibold text-surface-900 dark:text-surface-50">Checkout</h2>
          <button aria-label="Close" onClick={onClose} className="btn-icon btn-sm">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="px-6 py-4 space-y-5">
          {/* Order Summary */}
          <div className="space-y-1.5 rounded-lg bg-surface-50 p-4 dark:bg-surface-800">
            <div className="flex justify-between text-sm text-surface-600 dark:text-surface-300">
              <span>{totals.itemCount} item{totals.itemCount !== 1 ? 's' : ''}</span>
              <span>Subtotal: {formatCurrency(totals.subtotal)}</span>
            </div>
            {totals.discountAmount > 0 && (
              <div className="flex justify-between text-sm text-green-600 dark:text-green-400">
                <span>Discount</span>
                <span>-{formatCurrency(totals.discountAmount)}</span>
              </div>
            )}
            <div className="flex justify-between text-sm text-surface-600 dark:text-surface-300">
              <span>Tax</span>
              <span>{formatCurrency(totals.tax)}</span>
            </div>
            <div className="flex justify-between border-t border-surface-200 pt-1.5 text-base font-bold text-surface-900 dark:border-surface-600 dark:text-surface-50">
              <span>Total</span>
              <span>{formatCurrency(totals.total)}</span>
            </div>
          </div>

          {/* Membership Upsell Banner */}
          {showUpsell && bestTier && (
            <div
              className="rounded-lg border-2 p-3"
              style={{ borderColor: bestTierColor, backgroundColor: `${bestTierColor}0D` }}
            >
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-2 min-w-0">
                  <Sparkles className="h-5 w-5 shrink-0" style={{ color: bestTierColor }} />
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-surface-900 dark:text-surface-100 truncate">
                      Save {bestTier.discount_pct}% with {bestTier.name}!
                    </p>
                    <p className="text-xs text-surface-500 truncate">
                      {formatCurrency(bestTier.monthly_price)}/mo &mdash; {bestTier.discount_pct}% off {bestTier.discount_applies_to}
                    </p>
                  </div>
                </div>
                <button
                  onClick={() => {
                    setEnrollingTier(bestTier.id);
                    upsellSubscribeMut.mutate(bestTier.id);
                  }}
                  disabled={upsellSubscribeMut.isPending}
                  className="btn btn-xs shrink-0 !font-semibold hover:opacity-90"
                  style={{ backgroundColor: bestTierColor, color: bestTierTextColor }}
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
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 resize-none"
            />
          </div>

          {requireReferral && store.getState().cartItems.some((item) => item.type === 'repair') && (
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">
                Referral Source <span className="text-red-500">*</span>
              </label>
              <select
                value={meta.referralSource}
                onChange={(e) => setMeta({ referralSource: e.target.value })}
                className="w-full rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
              >
                <option value="">Select referral source...</option>
                {referralSources.map((src) => (
                  <option key={src.id} value={src.name}>{src.name}</option>
                ))}
              </select>
            </div>
          )}

          {/* Payment Method */}
          <div>
            <div className="mb-2 flex items-center justify-between">
              <p className="text-sm font-medium text-surface-700 dark:text-surface-300">Payment Method</p>
              <button
                onClick={() => {
                  if (!splitMode && !blockchypConfigured) {
                    setSplitPayments((payments) =>
                      payments.map((payment) =>
                        payment.method === 'Card' ? { ...payment, method: 'Other' } : payment,
                      ),
                    );
                  }
                  setSplitMode(!splitMode);
                }}
                className={cn(
                  'btn btn-xs rounded-md',
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
              <div className="grid grid-cols-3 gap-2">
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
                        'btn btn-md !h-auto flex-col !gap-1 border !p-3 !whitespace-normal',
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
                      aria-label={`Split payment ${idx + 1} method`}
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
                        <option key={key} value={key} disabled={key === 'Card' && !blockchypConfigured}>{label}</option>
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
                        className="w-full rounded-lg border border-surface-300 bg-white py-2 pl-6 pr-2 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:border-teal-500 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
                      />
                    </div>
                    {splitPayments.length > 2 && (
                      <button
                        onClick={() => setSplitPayments(splitPayments.filter((_, i) => i !== idx))}
                        className="btn-icon btn-xs hover:text-red-500"
                        aria-label="Remove split payment"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    )}
                  </div>
                ))}
                <div className="flex items-center justify-between">
                  {/* WEB-FH-022 (Fixer-B4 2026-04-25): cap split-payment rows
                      at 6. Modal layout (max-w-lg) overflows past 6 rows on
                      desktop, and the Android server caps payments.length at
                      20. Disabling the button at 6 prevents the modal-footer
                      hidden-by-overflow bug + the silent server-side 400. */}
                  <button
                    onClick={() => {
                      if (splitPayments.length >= 6) return;
                      setSplitPayments([...splitPayments, { method: 'Cash', amount: '' }]);
                    }}
                    disabled={splitPayments.length >= 6}
                    title={splitPayments.length >= 6 ? 'Maximum of 6 split payments' : undefined}
                    className="btn btn-xs !px-0 text-teal-600 hover:text-teal-700 dark:text-teal-400 disabled:cursor-not-allowed disabled:text-surface-400 disabled:hover:text-surface-400 dark:disabled:text-surface-500"
                  >
                    <Plus className="h-3.5 w-3.5" />
                    {splitPayments.length >= 6 ? 'Max 6 split payments' : 'Add Method'}
                  </button>
                  {splitRemainingCents > 0 ? (
                    <span className="text-xs font-medium text-amber-600 dark:text-amber-400">
                      Remaining: {formatCurrency(splitRemaining)}
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
                  className="w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-lg font-semibold focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:border-teal-500 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
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
                    className="btn btn-sm border border-surface-200 bg-white text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-300 dark:hover:bg-surface-700"
                  >
                    {formatCurrency(amt)}
                  </button>
                ))}
              </div>
              {cashAmount >= totals.total && (
                <div className="rounded-lg bg-green-50 px-4 py-2 text-center text-lg font-bold text-green-700 dark:bg-green-500/10 dark:text-green-400">
                  Change: {formatCurrency(change)}
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
            className="btn btn-xs !px-0 text-surface-500 hover:text-surface-700 dark:hover:text-surface-300"
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

        {/* WEB-UIUX-222: persistent inline terminal error — must be explicitly dismissed */}
        {terminalError && (
          <div
            role="alert"
            className="mx-6 mb-4 rounded-lg border border-red-300 bg-red-50 p-4 dark:border-red-700 dark:bg-red-900/20"
          >
            <div className="flex items-start gap-3">
              <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-red-600 dark:text-red-400" aria-hidden="true" />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-red-800 dark:text-red-300">Terminal Payment Failed</p>
                <p className="mt-1 text-sm text-red-700 dark:text-red-400">{terminalError}</p>
                <p className="mt-2 text-sm text-red-700 dark:text-red-400">
                  The invoice has been created.{' '}
                  {terminalErrorInvoiceId ? (
                    <Link
                      to={`/invoices/${terminalErrorInvoiceId}`}
                      className="font-medium underline underline-offset-2 hover:text-red-900 dark:hover:text-red-200"
                    >
                      Retry from the invoice page
                    </Link>
                  ) : (
                    <span className="font-medium">Retry from the invoice page.</span>
                  )}
                </p>
              </div>
              <button
                type="button"
                onClick={() => { setTerminalError(null); setTerminalErrorInvoiceId(null); }}
                className="shrink-0 rounded p-0.5 text-red-600 hover:bg-red-100 hover:text-red-800 dark:text-red-400 dark:hover:bg-red-800/30 dark:hover:text-red-200"
                aria-label="Dismiss error"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          </div>
        )}

        {/* Footer */}
        <div className="border-t border-surface-200 px-6 py-4 dark:border-surface-700">
          <button
            data-tutorial-target="checkout:complete-payment-button"
            onClick={handleCompleteCheckout}
            disabled={!canComplete}
            className={cn(
              'btn btn-lg w-full !font-semibold',
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
