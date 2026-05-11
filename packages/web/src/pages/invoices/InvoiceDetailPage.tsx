import React, { useState, useRef, useEffect } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, FileText, Plus, Loader2, DollarSign, Printer, Ban, MessageSquare, X, Smartphone, Undo2, Mail, Receipt, ReceiptText } from 'lucide-react'; // WEB-UIUX-1403: added ReceiptText for Credit Note / Refund button
import toast from 'react-hot-toast';
import { invoiceApi, settingsApi, smsApi, blockchypApi, notificationApi, installmentApi } from '@/api/endpoints';
import type { CreateInstallmentPlanInput } from '@/api/endpoints';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { confirm } from '@/stores/confirmStore';
import { PinModal } from '@/components/shared/PinModal';
import { PrintPreviewModal } from '@/components/shared/PrintPreviewModal';
import { useUndoableAction } from '@/hooks/useUndoableAction';
import { useFocusTrap } from '@/hooks/useFocusTrap';
import { useEscClose } from '@/hooks/useEscClose';
import { useHasRole } from '@/hooks/useHasRole';
import { cn } from '@/utils/cn';
import { Breadcrumb } from '@/components/shared/Breadcrumb';
import { formatCurrency, formatCurrencySymbol, formatDate, formatDateTime } from '@/utils/format';
// FA-L4: mount the "pay over time" (financing) + "split into installments"
// enrichment components near the record-payment actions so they are the
// first thing the cashier sees on an unpaid invoice.
import { FinancingButton } from '@/components/billing/FinancingButton';
import { InstallmentPlanWizard } from '@/components/billing/InstallmentPlanWizard';
// FA-L8 — replace the free-text credit note reason with the structured picker.
import {
  RefundReasonPicker,
  type RefundReasonCode,
} from '@/components/billing/RefundReasonPicker';
import type { InvoiceDetail, InvoiceCreditNote, InvoicePayment } from '@/types/invoice';

const STATUS_COLORS: Record<string, string> = {
  unpaid: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
  partial: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  paid: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  void: 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400',
  // WEB-UIUX-732: matched against InvoiceListPage / CustomerDetailPage maps so
  // imported RepairShopr/RepairDesk/MyRepairApp `refunded` invoices render a badge.
  refunded: 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400',
};

export function InvoiceDetailPage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const invoiceId = Number(id);
  const isValidId = id != null && !isNaN(invoiceId) && invoiceId > 0;
  // AUDIT-WEB-008: hold a cache snapshot taken just before optimistic void so
  // rollback works regardless of component mount state.
  const voidSnapshotRef = useRef<unknown>(undefined);
  const [showPayment, setShowPayment] = useState(false);
  const [showVoidConfirm, setShowVoidConfirm] = useState(false);
  // WEB-UIUX-1278: typed-confirm gate for high-value credit notes.
  const [showCreditNoteConfirm, setShowCreditNoteConfirm] = useState(false);
  // WEB-UIUX-1531: added transaction_id field for structured reference capture on non-cash payments.
  const [paymentForm, setPaymentForm] = useState({ amount: '', method: 'cash', notes: '', transaction_id: '' });
  const [showReceiptPrompt, setShowReceiptPrompt] = useState(false);
  const [showCreditNote, setShowCreditNote] = useState(false);
  // WEB-UIUX-877: manager PIN gate before credit-note for amounts > $100.
  const [showRefundPinGate, setShowRefundPinGate] = useState(false);
  const REFUND_PIN_THRESHOLD = 100;
  // WEB-UIUX-1052: renamed `reason` → `code` so the local field name matches
  // what it actually holds (a RefundReasonCode enum value). The composed
  // `reason` string (code + note) is still what we send to the server — see
  // creditNoteMutation.mutationFn below.
  const [creditNoteForm, setCreditNoteForm] = useState<{
    amount: string;
    code: RefundReasonCode | null;
    note: string;
  }>({ amount: '', code: null, note: '' });
  // WEB-UIUX-731: field-level error state for credit note form.
  // Populated from server error.response.data.fields (e.g. { amount: 'msg' })
  // or a generic fallback; cleared on any form change or successful mutation.
  const [creditNoteError, setCreditNoteError] = useState<{
    amount?: string;
    reason?: string;
    note?: string;
    _general?: string;
  }>({});
  // WEB-UIUX-1310: aria-live announcement for credit note success — mirrors toast for SR users.
  const [creditNoteSuccessAnnouncement, setCreditNoteSuccessAnnouncement] = useState('');
  const [emailReceiptSending, setEmailReceiptSending] = useState(false);
  const [showPrintModal, setShowPrintModal] = useState(false);
  // FA-L4: split-payment wizard lives behind a toggle so it doesn't crowd the
  // normal "record payment" flow. Opens only on demand, once per invoice.
  const [showInstallmentPlan, setShowInstallmentPlan] = useState(false);

  // Esc-to-close for the inline payment modal (Fixer-TT a11y). The credit-note
  // dialog handles Escape on its own overlay so the behavior stays scoped there.
  // WEB-UIUX-730: if both modals are open simultaneously (shouldn't happen via
  // normal flow but defensively) the credit-note dialog takes priority — Esc
  // closes it first; subsequent Esc closes the payment modal.
  useEffect(() => {
    if (!showPayment) return;
    function onKey(e: KeyboardEvent) {
      if (e.key !== 'Escape') return;
      // Credit-note overlay owns Esc when both open.
      if (showCreditNote) return;
      setShowPayment(false);
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [showPayment, showCreditNote]);

  // WEB-UIUX-729: focus-trap + Esc for the Credit Note dialog.
  // useFocusTrap returns a ref that must be attached to the inner dialog div.
  const creditNoteDialogRef = useFocusTrap(showCreditNote);
  // WEB-UIUX-1539: focus-trap for the Record Payment modal — mirrors credit-note pattern.
  const paymentDialogRef = useFocusTrap(showPayment);
  // WEB-UIUX-1210: gate Credit Note + Void behind admin/manager role.
  const canVoidOrCreditNote = useHasRole(['admin', 'manager']);
  // WEB-UIUX-1218: Esc handler checks dirty state before closing credit-note modal.
  useEscClose(() => {
    if (creditNoteForm.amount || creditNoteForm.code || creditNoteForm.note.trim()) {
      if (!window.confirm('Discard credit note?')) return;
    }
    setShowCreditNote(false);
  }, showCreditNote);

  const { data, isLoading } = useQuery({
    queryKey: ['invoice', id],
    queryFn: () => invoiceApi.get(invoiceId),
    enabled: isValidId,
  });

  const { data: pmData } = useQuery({
    queryKey: ['payment-methods'],
    queryFn: () => settingsApi.getPaymentMethods(),
  });

  const { data: bcData } = useQuery({
    queryKey: ['blockchyp', 'status'],
    queryFn: () => blockchypApi.status(),
    staleTime: 60000,
  });
  const blockchypEnabled = bcData?.data?.data?.enabled ?? false;
  const [terminalProcessing, setTerminalProcessing] = useState(false);

  // Server: res.json({ success: true, data: <flat invoice> }) — no extra .invoice nesting.
  const invoice: InvoiceDetail | undefined = data?.data?.data;
  const paymentMethods: any[] = pmData?.data?.data?.payment_methods || [];
  const currencySymbol = formatCurrencySymbol();

  // WEB-UIUX-1537: align paymentForm.method with the first enabled payment method when
  // paymentMethods loads, so 'cash' default doesn't silently mismatch a tenant that
  // has disabled cash and only shows card/ACH buttons.
  useEffect(() => {
    if (paymentMethods.length > 0 && !paymentMethods.some((pm: any) => pm.name.toLowerCase().replace(/\s+/g, '_') === paymentForm.method)) {
      setPaymentForm(p => ({ ...p, method: paymentMethods[0].name.toLowerCase().replace(/\s+/g, '_') }));
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [paymentMethods.length]);

  const payMutation = useMutation({
    mutationFn: (d: any) => invoiceApi.recordPayment(invoiceId, d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['invoice', id] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      toast.success('Payment recorded');
      setShowPayment(false);
      setPaymentForm({ amount: '', method: 'cash', notes: '', transaction_id: '' });
      setShowReceiptPrompt(true);
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to record payment'),
  });

  // Void is wrapped in a 5s undo window (D4-5). We optimistically show the
  // invoice as voided in the cache, then fire the server call after 5s unless
  // Undo is clicked. If Undo is clicked we invalidate to restore real state.
  const voidUndo = useUndoableAction<void>(
    async () => {
      await invoiceApi.void(invoiceId);
      queryClient.invalidateQueries({ queryKey: ['invoice', id] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
    },
    {
      timeoutMs: 5000,
      pendingMessage: 'Voiding invoice…',
      successMessage: 'Invoice voided',
      errorMessage: (_a, e: unknown) => {
        const err = e as { response?: { data?: { message?: string } } };
        return err?.response?.data?.message || 'Failed to void invoice';
      },
      onUndo: () => {
        // Immediately restore the pre-void snapshot so the UI reflects the
        // real state even if the server refetch is slow or the component is
        // unmounted by the time the response arrives.
        if (voidSnapshotRef.current !== undefined) {
          queryClient.setQueryData(['invoice', id], voidSnapshotRef.current);
        }
        queryClient.invalidateQueries({ queryKey: ['invoice', id] });
        queryClient.invalidateQueries({ queryKey: ['invoices'] });
      },
    },
  );

  const scheduleVoidInvoice = () => {
    // Snapshot BEFORE the optimistic write; stored in a ref so the onUndo
    // callback defined at hook-creation time can reach it.
    voidSnapshotRef.current = queryClient.getQueryData(['invoice', id]);

    // Optimistically mark the invoice as voided so the UI updates instantly.
    queryClient.setQueriesData({ queryKey: ['invoice', id] }, (old: any) => {
      if (!old) return old;
      const clone = structuredClone(old); // WEB-FO-012: structuredClone preserves Dates/undefined
      const inv = clone?.data?.data;
      if (inv) inv.status = 'void';
      return clone;
    });

    voidUndo.trigger();
  };

  const creditNoteMutation = useMutation({
    // WEB-W2-018: migration 150 added credit_note_code / credit_note_note
    // columns to invoices. Send code + note as dedicated fields; also keep
    // a composed `reason` string in case older server builds are still running.
    mutationFn: (d: { amount: number; code: RefundReasonCode; note: string }) => {
      // WEB-UIUX-1034: use ` — ` (en-dash) as the code/note separator instead
      // of a colon. A note like "see ticket #123 12:30pm" reintroduces the
      // colon and breaks any legacy `split(':')`-based reverse parser.
      // The dedicated credit_note_code + credit_note_note columns (migration
      // 150) are still the canonical source; this composed string is only a
      // legacy fallback.
      const reason = d.note
        ? `${d.code} — ${d.note}`
        : d.code;
      return invoiceApi.createCreditNote(invoiceId, {
        amount: d.amount,
        reason,
        code: d.code,
        note: d.note,
      });
    },
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ['invoice', id] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      // WEB-UIUX-715: status distribution donut chart reads ['invoice-stats'].
      queryClient.invalidateQueries({ queryKey: ['invoice-stats'] });
      // WEB-UIUX-431: build an informative refund destination message when
      // card info is available so operators can relay it to the customer.
      const cardPayment = invoice?.payments?.find(
        (p) => p.method_detail && !p.notes?.includes('[VOIDED]'),
      );
      const refundDest = cardPayment?.method_detail ?? null;
      const customerEmail = invoice?.customer_email ?? null;
      let msg = `Refund of ${formatCurrency(variables.amount)} issued`;
      if (refundDest) msg += ` to ${refundDest}`;
      if (customerEmail) msg += `. Receipt sent to ${customerEmail}`;
      if (!refundDest && !customerEmail) msg = 'Credit note created';

      // WEB-UIUX-1029: server returns the full credit note invoice in
      // _data.data.data. Extract order_id + id to show a navigable toast.
      const returnedCN = (_data as any)?.data?.data as import('@/types/invoice').InvoiceDetail | undefined;
      const cnOrderId = returnedCN?.order_id;
      const cnId = returnedCN?.id;
      // WEB-UIUX-1032: server now returns `meta.credit_overflow` and
      // `meta.store_credit_balance` so operators can tell the customer
      // exactly how much was parked as store credit + their new balance.
      const meta = (_data as any)?.data?.meta as { credit_overflow?: number; store_credit_balance?: number | null } | undefined;
      const overflow = Number(meta?.credit_overflow ?? 0);
      const newBalance = meta?.store_credit_balance != null ? Number(meta.store_credit_balance) : null;
      if (overflow > 0) {
        const balanceFrag = newBalance != null ? ` New balance: ${formatCurrency(newBalance)}.` : '';
        msg += ` · ${formatCurrency(overflow)} added to store credit.${balanceFrag}`;
      }
      if (cnOrderId && cnId) {
        toast.custom(
          (t) => (
            <div
              className={`flex items-center gap-3 bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded-lg shadow-lg px-4 py-3 text-sm ${t.visible ? 'opacity-100' : 'opacity-0'} transition-opacity`}
            >
              <span className="flex-1 text-surface-800 dark:text-surface-100">
                Credit note <span className="font-mono font-semibold">{cnOrderId}</span> · {formatCurrency(variables.amount)} refunded
                {overflow > 0 && (
                  <span className="block text-xs text-emerald-700 dark:text-emerald-300">
                    {formatCurrency(overflow)} added to store credit{newBalance != null ? ` · balance ${formatCurrency(newBalance)}` : ''}
                  </span>
                )}
              </span>
              <button
                onClick={() => { toast.dismiss(t.id); navigate(`/invoices/${cnId}`); }}
                className="shrink-0 text-primary-600 dark:text-primary-400 font-medium hover:underline"
              >
                Open
              </button>
            </div>
          ),
          { duration: 6000 },
        );
      } else {
        toast.success(msg);
      }

      // WEB-UIUX-1310: mirror success to aria-live region so SR users hear confirmation
      // even when the modal closes before the toast is read. Clear after 4s.
      const srMsg = cnOrderId ? `Credit note ${cnOrderId} created` : msg;
      setCreditNoteSuccessAnnouncement(srMsg);
      setTimeout(() => setCreditNoteSuccessAnnouncement(''), 4000);

      setShowCreditNote(false);
      setCreditNoteForm({ amount: '', code: null, note: '' });
      setCreditNoteError({});
      // WEB-UIUX-722: after credit note success, surface the same
      // SMS/email/skip prompt the payment flow uses so the customer
      // walks out with proof of refund.
      setShowReceiptPrompt(true);
    },
    onError: (e: any) => {
      const serverMsg: string = e?.response?.data?.message || 'Failed to create credit note';
      // WEB-UIUX-731: parse server-side field errors when available.
      // Server may return { fields: { amount?: string, reason?: string, note?: string } }
      const serverFields: Record<string, string> | undefined = e?.response?.data?.fields;
      if (serverFields && typeof serverFields === 'object' && Object.keys(serverFields).length > 0) {
        setCreditNoteError(serverFields as { amount?: string; reason?: string; note?: string });
      } else {
        setCreditNoteError({ _general: serverMsg });
      }
      toast.error(serverMsg);
    },
  });

  // Tip adjustment — wires the existing /blockchyp/adjust-tip endpoint.
  // Currently returns NOT_SUPPORTED; the dialog surfaces that gracefully.
  const [showTipAdjust, setShowTipAdjust] = useState(false);
  const [tipAdjustForm, setTipAdjustForm] = useState({ transaction_id: '', new_tip: '' });
  const tipAdjustMutation = useMutation({
    mutationFn: (d: { transaction_id: string; new_tip: number }) =>
      blockchypApi.adjustTip(d.transaction_id, d.new_tip),
    onSuccess: (res) => {
      const result = res.data?.data;
      if (!result?.success && result?.code === 'NOT_SUPPORTED') {
        toast.error('Tip adjustment not supported by current terminal');
      } else if (result?.success) {
        toast.success('Tip adjusted successfully');
        setShowTipAdjust(false);
      } else {
        toast.error(result?.error || 'Tip adjustment failed');
      }
    },
    onError: (e: unknown) => {
      const err = e as { response?: { data?: { message?: string } } };
      toast.error(err?.response?.data?.message || 'Tip adjustment failed');
    },
  });
  // Find the most recent card payment that has a processor_transaction_id
  const cardPaymentWithTxn = invoice?.payments?.find(
    (p) => p.processor_transaction_id && !p.notes?.includes('[VOIDED]'),
  );

  // FA-L4 — Installment plan creation mutation. Server route exists at
  // /api/v1/installments (see installment-plans.routes.ts). The wizard
  // already owns the money math + acceptance token; this just POSTs.
  const installmentPlanMutation = useMutation({
    mutationFn: (payload: CreateInstallmentPlanInput) => installmentApi.create(payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['invoice', id] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      toast.success('Installment plan created');
      setShowInstallmentPlan(false);
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to create plan'),
  });

  if (isLoading && isValidId) return <div className="flex items-center justify-center h-64"><Loader2 className="h-8 w-8 animate-spin text-surface-400" /></div>;
  if (!isValidId) return <div className="text-center py-20 text-surface-400">Invalid Invoice ID</div>;
  if (!invoice) return <div className="text-center py-20 text-surface-400">Invoice not found</div>;

  // WEB-UIUX-718: for $0 invoices with deposits/overpayments, amount_paid is
  // the refundable amount (not capped by total which is 0).
  // WEB-UIUX-1027: subtract prior credit notes to match the server cap.
  // Server caps at `original.total - SUM(prior credit notes)`. Client uses
  // invoice.credit_notes (already fetched with invoice detail) to derive the
  // same sum. This closes two failure modes:
  //   (a) partially-paid invoice: server allows up to full total, client was
  //       blocking at amount_paid only;
  //   (b) partially-credited invoice: client was allowing full amount_paid
  //       even after some credit was already issued.
  const sumOfPriorCreditNotes = (invoice.credit_notes ?? []).reduce(
    (acc, cn) => acc + Math.abs(Number(cn.total) || 0),
    0,
  );
  const serverCapForTotal = Math.max(0, Number(invoice.total) - sumOfPriorCreditNotes);
  const maxCreditNoteAmount = Math.max(
    0,
    Number(invoice.total) > 0
      ? Math.min(Number(invoice.amount_paid) || 0, serverCapForTotal)
      : Number(invoice.amount_paid) || 0,
  );
  const canCreateCreditNote = invoice.status !== 'void' && (Number(invoice.total) > 0 || Number(invoice.amount_paid) > 0) && maxCreditNoteAmount > 0;

  const handlePay = async () => {
    if (!paymentForm.amount || parseFloat(paymentForm.amount) <= 0) return toast.error('Enter a valid amount');
    // WEB-FH-021 (Fixer-B4 2026-04-25): warn the cashier before recording an
    // overpayment. The server happily accepts amounts that exceed amount_due
    // (it just leaves amount_due negative), so a fat-fingered extra zero
    // ($500 for a $50 balance) goes through silently. Tolerate small float
    // drift (0.005) so the "Pay full balance" preset never mis-fires.
    const enteredAmount = parseFloat(paymentForm.amount);
    const balanceDue = Number(invoice.amount_due) || 0;
    if (enteredAmount > balanceDue + 0.005) {
      const overage = enteredAmount - balanceDue;
      const proceed = await confirm(
        `Amount ${formatCurrency(enteredAmount)} exceeds the balance due of ${formatCurrency(balanceDue)} by ${formatCurrency(overage)}. Record this overpayment anyway?`,
        {
          title: 'Record overpayment?',
          confirmLabel: 'Record payment',
          danger: true,
        },
      );
      if (!proceed) return;
    }
    payMutation.mutate(paymentForm);
  };

  const handleTerminalPay = async () => {
    setTerminalProcessing(true);
    try {
      const res = await blockchypApi.processPayment(invoiceId);
      const result = res.data?.data;
      // @audit-fixed (WEB-FN-004 / Fixer-K 2026-04-24): the server returns
      // HTTP 202 with `{ success: false, data: { status: 'pending_reconciliation' } }`
      // when the terminal charge outcome is unknown (SEC-M34). Previously the UI
      // treated that as a generic decline and hid the transactionRef the operator
      // needs to reconcile by hand. Branch explicitly so the operator sees a
      // distinct, non-retryable state and the receipt prompt does NOT open.
      if (res.status === 202 || result?.status === 'pending_reconciliation') {
        toast.error(
          `Terminal outcome unknown — pending reconciliation${result?.transactionRef ? ` (ref ${result.transactionRef})` : ''}. Verify with the terminal before retrying.`,
          { duration: 8000 },
        );
        // Refresh invoice in case server already wrote a payment row before timeout.
        queryClient.invalidateQueries({ queryKey: ['invoice', id] });
        return;
      }
      if (result?.success) {
        // @audit-fixed: surface idempotency replay so the operator knows the
        // charge wasn't re-attempted. Avoids double-prompting for receipts on a
        // refresh-after-success.
        if (result.replayed) {
          toast.success(`Payment already captured — using prior charge${result.cardType ? ` (${result.cardType} ending ${result.last4})` : ''}`);
        } else {
          toast.success(`Payment approved${result.cardType ? ` — ${result.cardType} ending ${result.last4}` : ''}`);
        }
        queryClient.invalidateQueries({ queryKey: ['invoice', id] });
        queryClient.invalidateQueries({ queryKey: ['invoices'] });
        setShowPayment(false);
        setShowReceiptPrompt(true);
      } else {
        toast.error(result?.error || result?.responseDescription || 'Payment declined');
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Terminal communication failed';
      toast.error(`Terminal error: ${msg}`);
    } finally {
      setTerminalProcessing(false);
    }
  };

  // WEB-UIUX-1278: threshold above which typed-confirm is required.
  // Triggers when amount >= invoice total OR >= $500.
  const CREDIT_NOTE_TYPED_THRESHOLD = 500;

  const handleCreditNote = () => {
    const amount = parseFloat(creditNoteForm.amount);
    // WEB-UIUX-1390: collect all field errors before showing any feedback so the
    // operator sees every problem at once instead of one toast per issue.
    const fieldErrors: { amount?: string; reason?: string; note?: string } = {};
    if (!amount || amount < 0.01) {
      fieldErrors.amount = 'Minimum credit note amount is 0.01';
    } else if (amount > maxCreditNoteAmount) {
      // @audit-fixed (WEB-FF-003 / Fixer-PP 2026-04-25): tenant-aware currency.
      fieldErrors.amount = `Amount cannot exceed credit-note max (${formatCurrency(maxCreditNoteAmount)})`;
    }
    if (!creditNoteForm.code) {
      fieldErrors.reason = 'Select a reason';
    } else if (creditNoteForm.code === 'other' && !creditNoteForm.note.trim()) {
      fieldErrors.note = 'Please enter a note when selecting "Other" as the reason';
    }
    if (Object.keys(fieldErrors).length > 0) {
      setCreditNoteError(fieldErrors);
      return;
    }
    setCreditNoteError({});
    // WEB-UIUX-1278: high-value credit notes (>= invoice total OR >= $500) require
    // the operator to type the invoice number to confirm — same pattern as Void.
    // Lower amounts fire immediately; the filled credit-note form itself is the
    // confirm step (operator has already reviewed amount + reason before clicking).
    const isHighValue =
      amount >= Number(invoice.total) || amount >= CREDIT_NOTE_TYPED_THRESHOLD;
    if (isHighValue) {
      setShowCreditNoteConfirm(true);
      return;
    }
    creditNoteMutation.mutate({
      amount,
      code: creditNoteForm.code as RefundReasonCode,
      note: creditNoteForm.note.trim(),
    });
  };

  const handleEmailReceipt = async () => {
    const email = invoice.customer_email;
    if (!email) return toast.error('No email address on file for this customer');
    setEmailReceiptSending(true);
    try {
      await notificationApi.sendReceipt({ invoice_id: invoiceId, email });
      toast.success('Receipt emailed to ' + email);
      setShowReceiptPrompt(false);
    } catch (err: any) {
      toast.error(err?.response?.data?.message || 'Failed to email receipt');
    } finally {
      setEmailReceiptSending(false);
    }
  };

  return (
    <div>
      {/* WEB-UIUX-1310: visually-hidden aria-live region announces credit note success to SR users. */}
      <span
        aria-live="polite"
        aria-atomic="true"
        className="sr-only"
      >
        {creditNoteSuccessAnnouncement}
      </span>
      <Breadcrumb items={[
        { label: 'Invoices', href: '/invoices' },
        { label: invoice.order_id || `INV-${id}` },
      ]} />
      <div className="mb-6">
        <div className="flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">{invoice.order_id}</h1>
            <span className={cn('inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium capitalize', STATUS_COLORS[invoice.status] || '')}>
              {invoice.status}
            </span>
            {/* WEB-UIUX-1031: when this invoice is a credit note, link back to
                the original invoice so operators can navigate without searching. */}
            {invoice.credit_note_for != null && (
              <Link
                to={`/invoices/${invoice.credit_note_for}`}
                className="inline-flex items-center gap-1 text-xs font-medium text-amber-600 dark:text-amber-400 hover:underline"
              >
                <Receipt className="h-3.5 w-3.5" />
                Credit note for {invoice.credit_note_for_order_id ?? `INV-${invoice.credit_note_for}`}
              </Link>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-2">
            {invoice.status !== 'void' && invoice.status !== 'paid' && (
              <>
                {/* FA-L4 — offer the "split into installments" wizard for
                    invoices with an outstanding balance. The wizard caps
                    at 2–24 payments and locks money math to integer cents. */}
                {Number(invoice.amount_due) > 0 && (
                  <button
                    onClick={() => setShowInstallmentPlan(true)}
                    className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-indigo-200 dark:border-indigo-800 text-indigo-600 dark:text-indigo-400 hover:bg-indigo-50 dark:hover:bg-indigo-900/20 transition-colors"
                  >
                    Payment Plan
                  </button>
                )}
                {/* FA-L4 — Affirm/Klarna financing CTA. Only renders above
                    the provider min ($500). Stub modal until API keys land. */}
                <FinancingButton
                  amountCents={Math.round(Number(invoice.amount_due) * 100)}
                  enabled={Number(invoice.amount_due) > 0}
                />
              </>
            )}
            <button onClick={() => setShowPrintModal(true)} className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
              <Printer className="h-4 w-4" /> Print
            </button>
            {/* WEB-UIUX-1210: gate behind admin/manager; hide entirely or show
                disabled with tooltip when user lacks the required role. */}
            {/* WEB-UIUX-1304: show disabled Refund button when no payment has been made yet
                (amount_paid===0 means maxCreditNoteAmount===0, so canCreateCreditNote is false).
                This gives operators a clear signal rather than silently hiding the action. */}
            {invoice.status !== 'void' && (canCreateCreditNote || Number(invoice.amount_paid) <= 0) && (
              !canCreateCreditNote && Number(invoice.amount_paid) <= 0 ? (
                <button
                  disabled
                  title="No payments yet — nothing to refund"
                  className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-red-100 dark:border-red-900/40 text-red-300 dark:text-red-700 cursor-not-allowed opacity-60"
                >
                  <Undo2 className="h-4 w-4" /> Refund
                </button>
              ) : canVoidOrCreditNote ? (
                <button
                  onClick={() => {
                    // WEB-UIUX-877: require manager PIN for refunds above threshold.
                    if (maxCreditNoteAmount > REFUND_PIN_THRESHOLD) {
                      setShowRefundPinGate(true);
                    } else {
                      setShowCreditNote(true);
                    }
                  }}
                  // WEB-UIUX-1040: switched from amber to red ramp — amber read
                  // as "soft action"; Credit Note is irreversible like Void. Icon
                  // + label still distinguish it from the Void button.
                  // WEB-UIUX-1279: relabelled entry-point button to "Refund";
                  // modal title "Issue Credit Note" stays for accounting clarity.
                  // WEB-UIUX-1403: swapped Undo2 → ReceiptText; CreditCard had payment-card semantics.
                  className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-red-200 dark:border-red-800 text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                >
                  <ReceiptText className="h-4 w-4" /> Refund
                </button>
              ) : (
                <button
                  disabled
                  title="Manager permission required"
                  className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-red-100 dark:border-red-900/40 text-red-300 dark:text-red-700 cursor-not-allowed opacity-60"
                >
                  <ReceiptText className="h-4 w-4" /> Refund
                </button>
              )
            )}
            {/* WEB-W2-017: Tip-adjust removed — BlockChyp SDK does not expose
                adjustTip. Re-enable when SDK ships the endpoint. Void + re-charge
                is the current workaround per the server's NOT_SUPPORTED response. */}
            {/* WEB-UIUX-1210: Void also gated behind admin/manager role. */}
            {invoice.status !== 'void' && (
              canVoidOrCreditNote ? (
                <button onClick={() => setShowVoidConfirm(true)} className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-red-200 dark:border-red-800 text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors">
                  <Ban className="h-4 w-4" /> Void
                </button>
              ) : (
                <button
                  disabled
                  title="Manager permission required"
                  className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-red-100 dark:border-red-900/40 text-red-300 dark:text-red-700 cursor-not-allowed opacity-60"
                >
                  <Ban className="h-4 w-4" /> Void
                </button>
              )
            )}
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main Content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Customer & Date */}
          <div className="card p-6">
            <div className="flex justify-between gap-4">
              <div>
                <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-2">Bill To</h2>
                <Link to={`/customers/${invoice.customer_id}`} className="font-semibold text-surface-900 dark:text-surface-100 hover:text-primary-600 transition-colors">
                  {invoice.first_name} {invoice.last_name}
                </Link>
                {invoice.organization && <p className="text-sm text-surface-500">{invoice.organization}</p>}
                {invoice.customer_phone && <p className="text-sm text-surface-500">{invoice.customer_phone}</p>}
                {invoice.customer_email && <p className="text-sm text-surface-500">{invoice.customer_email}</p>}
              </div>
              <div className="text-right">
                <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-2">Invoice</h2>
                <p className="font-mono font-semibold text-surface-900 dark:text-surface-100">{invoice.order_id}</p>
                {/* @audit-fixed: use formatDate helper instead of hardcoded en-US locale */}
                <p className="text-sm text-surface-500">{formatDate(invoice.created_at)}</p>
                {invoice.due_on && (
                  <p className="text-sm text-surface-500">Due: {formatDate(invoice.due_on)}</p>
                )}
                {invoice.ticket_id && (
                  invoice.ticket_is_deleted
                    ? <span className="text-sm text-surface-400 dark:text-surface-500">Ticket #{invoice.ticket_id} <span className="italic">(deleted)</span></span>
                    : <Link to={`/tickets/${invoice.ticket_id}`} className="text-sm text-primary-600 dark:text-primary-400 hover:underline">
                        Ticket #{invoice.ticket_id}
                      </Link>
                )}
              </div>
            </div>
          </div>

          {/* Line Items */}
          <div className="card overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-surface-200 dark:border-surface-700">
                  {['Description', 'Qty', 'Unit Price', 'Tax', 'Total'].map((h) => (
                    <th key={h} className={cn('px-4 py-3 text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50', h === 'Description' ? 'text-left' : 'text-right')}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-surface-100 dark:divide-surface-700/50">
                {/* @audit-fixed: hardcoded "$" + toFixed replaced with formatCurrency */}
                {invoice.line_items?.map((li: any) => (
                  <tr key={li.id}>
                    <td className="px-4 py-3 text-sm text-surface-900 dark:text-surface-100">
                      {li.description}
                      {li.notes && <p className="text-xs text-surface-400">{li.notes}</p>}
                    </td>
                    <td className="px-4 py-3 text-sm text-right text-surface-600 dark:text-surface-300">{li.quantity}</td>
                    <td className="px-4 py-3 text-sm text-right text-surface-600 dark:text-surface-300">{formatCurrency(li.unit_price)}</td>
                    <td className="px-4 py-3 text-sm text-right text-surface-500">{formatCurrency(li.tax_amount)}</td>
                    <td className="px-4 py-3 text-sm text-right font-medium text-surface-900 dark:text-surface-100">{formatCurrency(li.total)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {/* Totals */}
            {/* @audit-fixed: hardcoded "$" + toFixed replaced with formatCurrency */}
            <div className="border-t border-surface-200 dark:border-surface-700 px-4 py-4">
              <div className="max-w-xs ml-auto space-y-1.5 text-sm">
                <div className="flex justify-between text-surface-600 dark:text-surface-300">
                  <span>Subtotal</span><span>{formatCurrency(invoice.subtotal)}</span>
                </div>
                {invoice.discount > 0 && (
                  <div className="flex justify-between text-green-600 dark:text-green-400">
                    <span>Discount {invoice.discount_reason && `(${invoice.discount_reason})`}</span>
                    <span>-{formatCurrency(invoice.discount)}</span>
                  </div>
                )}
                <div className="flex justify-between text-surface-600 dark:text-surface-300">
                  <span>Tax</span><span>{formatCurrency(invoice.total_tax)}</span>
                </div>
                <div className="flex justify-between font-bold text-base text-surface-900 dark:text-surface-100 border-t border-surface-200 dark:border-surface-700 pt-2 mt-2">
                  <span>Total</span><span>{formatCurrency(invoice.total)}</span>
                </div>
              </div>
            </div>
          </div>

          {/* Payment History Timeline */}
          {invoice.payments?.length > 0 && (
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Payment Timeline</h2>
              <div className="relative">
                {/* Vertical line */}
                {invoice.payments.length > 1 && (
                  <div className="absolute left-[15px] top-2 bottom-2 w-0.5 bg-surface-200 dark:bg-surface-700" />
                )}
                <div className="space-y-4">
                  {invoice.payments.map((p: any, idx: number) => {
                    const isVoided = p.notes?.includes('[VOIDED]');
                    const runningTotal = invoice.payments
                      .slice(0, idx + 1)
                      .reduce((sum: number, pay: any) => {
                        if (pay.notes?.includes('[VOIDED]')) return sum;
                        return sum + Number(pay.amount);
                      }, 0);
                    return (
                      <div key={p.id} className="relative flex gap-3">
                        {/* Timeline dot */}
                        <div className={cn(
                          'relative z-10 mt-0.5 flex h-[30px] w-[30px] flex-shrink-0 items-center justify-center rounded-full border-2',
                          isVoided
                            ? 'border-red-300 bg-red-50 dark:border-red-700 dark:bg-red-900/30'
                            : 'border-green-300 bg-green-50 dark:border-green-700 dark:bg-green-900/30'
                        )}>
                          <DollarSign className={cn('h-3.5 w-3.5', isVoided ? 'text-red-500' : 'text-green-600 dark:text-green-400')} />
                        </div>
                        {/* Content */}
                        <div className="flex-1 min-w-0">
                          <div className="flex items-start justify-between gap-2">
                            <div>
                              <span className={cn(
                                'text-sm font-medium capitalize',
                                isVoided ? 'text-red-500 line-through' : 'text-surface-900 dark:text-surface-100'
                              )}>
                                {p.method}
                              </span>
                              {p.method_detail && <span className="text-xs text-surface-400 ml-1">({p.method_detail})</span>}
                              {isVoided && <span className="ml-1.5 text-xs font-semibold text-red-500">VOIDED</span>}
                            </div>
                            <span className={cn(
                              'font-semibold tabular-nums',
                              isVoided ? 'text-red-400 line-through text-sm' : 'text-green-600 dark:text-green-400'
                            )}>
                              {/* @audit-fixed: use formatCurrency */}
                              {formatCurrency(p.amount)}
                            </span>
                          </div>
                          <div className="flex items-center gap-1.5 mt-0.5">
                            <time className="text-xs text-surface-400">
                              {/* @audit-fixed: use formatDateTime helper */}
                              {formatDateTime(p.created_at)}
                            </time>
                            {p.recorded_by && (
                              <span className="text-xs text-surface-400">
                                &middot; {p.recorded_by}
                              </span>
                            )}
                          </div>
                          {p.notes && !isVoided && (
                            <p className="text-xs text-surface-400 mt-0.5">{p.notes}</p>
                          )}
                          {!isVoided && (
                            <p className="text-xs text-surface-400 mt-0.5">
                              {/* @audit-fixed: use formatCurrency */}
                              Running total: {formatCurrency(runningTotal)} of {formatCurrency(invoice.total)}
                            </p>
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          )}

          {/* WEB-UIUX-707: Credit Notes Issued */}
          {(invoice.credit_notes ?? []).length > 0 && (
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Credit Notes Issued</h2>
              <div className="divide-y divide-surface-100 dark:divide-surface-700/50">
                {(invoice.credit_notes as InvoiceCreditNote[]).map((cn) => {
                  const reason = cn.credit_note_code
                    ? (cn.credit_note_note ? `${cn.credit_note_code}: ${cn.credit_note_note}` : cn.credit_note_code)
                    : (cn.notes ?? null);
                  return (
                    <div key={cn.id} className="py-3 flex items-start justify-between gap-4">
                      <div className="min-w-0">
                        <p className="text-sm font-medium text-surface-900 dark:text-surface-100 font-mono">{cn.order_id}</p>
                        <time className="text-xs text-surface-400">{formatDate(cn.created_at)}</time>
                        {reason && (
                          <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5 truncate" title={reason}>{reason}</p>
                        )}
                      </div>
                      <span className="shrink-0 font-semibold text-amber-600 dark:text-amber-400 tabular-nums">
                        -{formatCurrency(Math.abs(cn.total))}
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>

        {/* Right Panel */}
        <div className="space-y-6">
          {/* Summary */}
          {/* @audit-fixed: hardcoded "$" + toFixed replaced with formatCurrency */}
          <div className="card p-6">
            <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Summary</h2>
            <div className="space-y-3">
              <div className="flex justify-between text-sm">
                <span className="text-surface-600 dark:text-surface-300">Total</span>
                <span className="font-semibold text-surface-900 dark:text-surface-100">{formatCurrency(invoice.total)}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-surface-600 dark:text-surface-300">Paid</span>
                <span className="font-semibold text-green-600 dark:text-green-400">{formatCurrency(invoice.amount_paid)}</span>
              </div>
              <div className="flex justify-between text-sm border-t border-surface-200 dark:border-surface-700 pt-3 mt-1">
                <span className="font-semibold text-surface-700 dark:text-surface-200">Balance Due</span>
                <span className={cn('font-bold text-base', Number(invoice.amount_due) > 0 ? 'text-red-600 dark:text-red-400' : 'text-green-600 dark:text-green-400')}>
                  {formatCurrency(invoice.amount_due)}
                </span>
              </div>
            </div>
            {invoice.status !== 'void' && invoice.status !== 'paid' && (
              <button onClick={() => setShowPayment(true)} className="w-full mt-4 inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-primary-600 hover:bg-primary-700 text-primary-950 rounded-lg text-sm font-medium transition-colors">
                <DollarSign className="h-4 w-4" /> Record Payment
              </button>
            )}
          </div>

          {/* Notes */}
          {invoice.notes && (
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-2">Notes</h2>
              <p className="text-sm text-surface-700 dark:text-surface-300">{invoice.notes}</p>
            </div>
          )}
        </div>
      </div>

      {/* Payment Modal */}
      {showPayment && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="record-payment-title"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
          // WEB-UIUX-1529: dirty-check on backdrop click prevents accidental loss of
          // a partially-entered payment; operator must confirm before data is discarded.
          onClick={(e) => {
            if (e.target !== e.currentTarget) return;
            if (paymentForm.amount || paymentForm.notes || paymentForm.method !== 'cash') {
              if (!window.confirm('Discard payment entry?')) return;
            }
            setShowPayment(false);
            setPaymentForm({ amount: '', method: 'cash', notes: '', transaction_id: '' });
          }}
        >
          {/* WEB-UIUX-1539: paymentDialogRef wired here so useFocusTrap traps focus inside Payment modal. */}
          <div ref={paymentDialogRef as React.RefObject<HTMLDivElement>} className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-md p-6" onClick={(e) => e.stopPropagation()}>
            <h2 id="record-payment-title" className="text-lg font-bold text-surface-900 dark:text-surface-100 mb-4">Record Payment</h2>
            <div className="space-y-4">
              <div>
                {/* WEB-UIUX-1535: prominent primary preset button above the amount input so
                    the cashier can one-tap the full balance without hunting for a tiny link. */}
                <button
                  onClick={() => setPaymentForm({ ...paymentForm, amount: Number(invoice.amount_due).toFixed(2) })}
                  className="w-full mb-2 px-4 py-2.5 bg-primary-600 hover:bg-primary-700 text-primary-950 rounded-lg text-sm font-semibold transition-colors"
                >
                  Pay {formatCurrency(invoice.amount_due)} (full balance)
                </button>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Amount</label>
                <div className="relative">
                  <span aria-hidden="true" className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-surface-400">{currencySymbol}</span>
                  <input
                    id="payment-amount"
                    type="number" step="0.01" min="0.01"
                    value={paymentForm.amount}
                    onChange={(e) => setPaymentForm({ ...paymentForm, amount: e.target.value })}
                    placeholder={Number(invoice.amount_due).toFixed(2)}
                    aria-invalid={paymentForm.amount !== '' && parseFloat(paymentForm.amount) <= 0 ? true : undefined}
                    aria-describedby="payment-amount-label"
                    className="input w-full pl-12"
                    autoFocus
                  />
                </div>
              </div>
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Payment Method</label>
                {/* WEB-UIUX-1542: flex-wrap so 5+ methods wrap gracefully without orphans */}
                <div className="flex flex-wrap gap-2">
                  {(paymentMethods.length > 0 ? paymentMethods : [{ id: 'cash', name: 'Cash' }, { id: 'credit_card', name: 'Credit Card' }, { id: 'debit', name: 'Debit Card' }, { id: 'other', name: 'Other' }]).map((pm: any) => (
                    <button
                      key={pm.id || pm.name}
                      onClick={() => setPaymentForm({ ...paymentForm, method: pm.name.toLowerCase().replace(/\s+/g, '_') })}
                      className={cn('px-3 py-2 text-sm font-medium rounded-lg border transition-colors min-w-[6rem]',
                        paymentForm.method === pm.name.toLowerCase().replace(/\s+/g, '_')
                          ? 'bg-primary-600 text-primary-950 border-primary-600'
                          : 'border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800'
                      )}
                    >
                      {pm.name}
                    </button>
                  ))}
                </div>
              </div>
              {/* WEB-UIUX-1531: structured transaction_id field — only shown for non-cash methods
                  so card/ACH/etc payments capture the reference in a dedicated field. */}
              {paymentForm.method !== 'cash' && (
                <div>
                  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Reference / Transaction ID</label>
                  <input
                    value={paymentForm.transaction_id}
                    onChange={(e) => setPaymentForm({ ...paymentForm, transaction_id: e.target.value })}
                    className="input w-full"
                    placeholder="e.g. card auth code, check number"
                  />
                </div>
              )}
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Notes (optional)</label>
                {/* WEB-UIUX-1540: now that transaction_id is its own field, notes is for free-form memo text */}
                <input value={paymentForm.notes} onChange={(e) => setPaymentForm({ ...paymentForm, notes: e.target.value })} className="input w-full" placeholder="Memo (e.g., 'invoice paid at front desk')" />
              </div>
            </div>
            {blockchypEnabled && (
              <button
                onClick={handleTerminalPay}
                disabled={terminalProcessing || payMutation.isPending}
                className="w-full mt-4 flex items-center justify-center gap-2 px-4 py-3 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-bold transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
              >
                {terminalProcessing ? (
                  <><Loader2 className="h-4 w-4 animate-spin" /> Waiting for terminal...</>
                ) : (
                  <><Smartphone className="h-4 w-4" /> Pay {formatCurrency(invoice.amount_due)} via Terminal</>
                )}
              </button>
            )}
            {blockchypEnabled && (
              <div className="relative my-3">
                <div className="absolute inset-0 flex items-center"><div className="w-full border-t border-surface-200 dark:border-surface-700" /></div>
                <div className="relative flex justify-center text-xs"><span className="bg-white dark:bg-surface-900 px-2 text-surface-400">or record manually</span></div>
              </div>
            )}
            <div className="flex gap-3">
              <button onClick={() => setShowPayment(false)} className="flex-1 px-4 py-2.5 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">Cancel</button>
              <button onClick={handlePay} disabled={payMutation.isPending || terminalProcessing} className="flex-1 px-4 py-2.5 bg-primary-600 hover:bg-primary-700 text-primary-950 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none">
                {payMutation.isPending ? 'Recording...' : 'Record Payment'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Receipt prompt after payment */}
      {showReceiptPrompt && (
        // WEB-UIUX-1527: backdrop click now fires an info toast instead of silently closing,
        // so the cashier knows the receipt was skipped and can re-send from Payment Timeline.
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 backdrop-blur-sm" onClick={() => { setShowReceiptPrompt(false); toast('Receipt skipped — re-send from Payment Timeline'); }}>
          <div className="w-full max-w-sm rounded-xl border border-surface-200 bg-white p-6 shadow-2xl dark:border-surface-700 dark:bg-surface-800" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100">Send Receipt?</h3>
              <button aria-label="Close" onClick={() => setShowReceiptPrompt(false)} className="rounded p-1 text-surface-400 hover:text-surface-600">
                <X className="h-4 w-4" />
              </button>
            </div>
            <p className="text-sm text-surface-500 dark:text-surface-400 mb-4">Payment recorded successfully. How would you like to send the receipt?</p>
            <div className="flex flex-col gap-2">
              <button
                onClick={() => {
                  setShowReceiptPrompt(false);
                  setShowPrintModal(true);
                }}
                className="flex items-center gap-2 rounded-lg border border-surface-200 dark:border-surface-700 px-4 py-2.5 text-sm font-medium text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-700 transition-colors"
              >
                <Printer className="h-4 w-4" />
                Print Receipt
              </button>
              {invoice?.customer_phone && (
                <button
                  onClick={() => {
                    const phone = invoice.customer_phone;
                    if (!phone) return;
                    const msg = `Receipt for Invoice #${invoice.order_id || id}: Total ${formatCurrency(invoice.total)}. Thank you for your business!`;
                    smsApi.send({ to: phone, message: msg, entity_type: 'invoice', entity_id: invoiceId })
                      .then(() => toast.success('Receipt sent via SMS'))
                      .catch(() => toast.error('Failed to send SMS'));
                    setShowReceiptPrompt(false);
                  }}
                  className="flex items-center gap-2 rounded-lg border border-green-200 dark:border-green-800 px-4 py-2.5 text-sm font-medium text-green-700 dark:text-green-400 hover:bg-green-50 dark:hover:bg-green-900/20 transition-colors"
                >
                  <MessageSquare className="h-4 w-4" />
                  Send via SMS
                </button>
              )}
              {invoice?.customer_email && (
                <button
                  onClick={handleEmailReceipt}
                  disabled={emailReceiptSending}
                  className="flex items-center gap-2 rounded-lg border border-blue-200 dark:border-blue-800 px-4 py-2.5 text-sm font-medium text-blue-700 dark:text-blue-400 hover:bg-blue-50 dark:hover:bg-blue-900/20 transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                >
                  <Mail className="h-4 w-4" />
                  {emailReceiptSending ? 'Sending...' : `Email to ${invoice.customer_email}`}
                </button>
              )}
              <button
                onClick={() => setShowReceiptPrompt(false)}
                className="text-sm text-surface-400 hover:text-surface-600 dark:hover:text-surface-300 py-1 transition-colors"
              >
                Skip
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Credit Note Modal */}
      {showCreditNote && canCreateCreditNote && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="credit-note-title"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
          onClick={(e) => {
            if (e.target !== e.currentTarget) return;
            // WEB-UIUX-1046: only close on backdrop-click when the form is
            // untouched. If any field is dirty, require an explicit confirm so
            // the operator doesn't accidentally lose a partially-entered note.
            const isDirty =
              creditNoteForm.amount !== '' ||
              creditNoteForm.code !== null ||
              creditNoteForm.note.trim() !== '';
            if (isDirty) {
              if (!window.confirm('Discard credit-note in progress?')) return;
            }
            setShowCreditNote(false);
            setCreditNoteForm({ amount: '', code: null, note: '' });
          }}
        >
          {/* WEB-UIUX-1302: creditNoteDialogRef wired here so useFocusTrap traps focus inside Credit Note dialog. */}
          <div ref={creditNoteDialogRef as React.RefObject<HTMLDivElement>} className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-md p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              {/* WEB-UIUX-1054: "Issue" is more precise — the action issues a
                  credit instrument; "Create" is too generic. */}
              <h2 id="credit-note-title" className="text-lg font-bold text-surface-900 dark:text-surface-100">Issue Credit Note</h2>
              <button aria-label="Close" onClick={() => { setShowCreditNote(false); setCreditNoteForm({ amount: '', code: null, note: '' }); setCreditNoteError({}); }} className="rounded p-1 text-surface-400 hover:text-surface-600">
                <X className="h-4 w-4" />
              </button>
            </div>
            {/* WEB-UIUX-1214: when amount_due is 0, every dollar of the credit note
                becomes store credit — surface this prominently so the operator
                knows the overflow path is active before they submit. */}
            {Number(invoice.amount_due) <= 0 && (() => {
              const enteredAmt = parseFloat(creditNoteForm.amount);
              const hasAmt = !isNaN(enteredAmt) && enteredAmt > 0;
              return (
                <div className="mb-3 rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/20 px-3 py-2 text-xs text-amber-700 dark:text-amber-300 font-medium">
                  {hasAmt
                    ? `Excess of ${formatCurrency(enteredAmt)} will be issued as customer store credit`
                    : 'This invoice is fully paid — the entire credit will be issued as customer store credit'}
                </div>
              );
            })()}
            {/* WEB-UIUX-435: outcome-preview — show what will happen, not just what the action is */}
            {/* WEB-UIUX-711: store-credit overflow preview when amount > amount_due */}
            <div className="text-sm text-surface-500 dark:text-surface-400 mb-4">
              {(() => {
                const enteredAmount = parseFloat(creditNoteForm.amount);
                const hasAmount = !isNaN(enteredAmount) && enteredAmount > 0;
                const displayAmount = hasAmount ? formatCurrency(enteredAmount) : null;
                const balanceDue = Number(invoice.amount_due) || 0;

                if (balanceDue > 0 && hasAmount) {
                  const appliedToBalance = Math.min(enteredAmount, balanceDue);
                  const storeCreditOverflow = Math.max(0, enteredAmount - balanceDue);
                  if (storeCreditOverflow > 0.004) {
                    // Amount exceeds remaining balance — split preview
                    return (
                      <div className="space-y-2">
                        <p>{displayAmount} will be applied as follows:</p>
                        <ul className="list-disc list-inside space-y-1 text-xs">
                          <li><span className="font-medium text-surface-700 dark:text-surface-200">{formatCurrency(appliedToBalance)}</span> will reduce the outstanding balance on invoice {invoice.order_id} to $0.</li>
                          <li><span className="font-medium text-surface-700 dark:text-surface-200">{formatCurrency(storeCreditOverflow)}</span> will be added to the customer's store credit balance.</li>
                        </ul>
                        <p className="text-xs text-amber-700 dark:text-amber-300 font-medium">Total credit applied: {displayAmount}</p>
                      </div>
                    );
                  }
                  // Amount ≤ balance — simple balance reduction
                  return (
                    <p>{displayAmount} will be deducted from the outstanding balance on invoice {invoice.order_id}.</p>
                  );
                }

                if (balanceDue > 0) {
                  // No amount entered yet
                  // WEB-UIUX-1222: copy is accurate for amount_due > 0; the else branch below
                  // handles amount_due = 0 so "reduce the outstanding balance" is never shown falsely.
                  return <p>Issue a credit note against invoice {invoice.order_id}. This will reduce the outstanding balance.</p>;
                }

                // Fully paid (amount_due = 0) — credit goes to store credit, not balance reduction
                // WEB-UIUX-1222: use accurate copy when outstanding balance is already zero.
                const payments: InvoicePayment[] = invoice.payments ?? [];
                const latestPayment = payments
                  .filter((p) => p.method !== 'credit_note')
                  .sort((a, b) => b.amount - a.amount)[0];
                const methodLabel = latestPayment
                  ? `${latestPayment.method_detail || latestPayment.method}`
                  : null;
                if (displayAmount && methodLabel) {
                  return <p>{displayAmount} will be refunded to the {methodLabel} used for this invoice, typically within 3–5 business days.</p>;
                } else if (displayAmount) {
                  return <p>{displayAmount} will be refunded to the original payment method, typically within 3–5 business days.</p>;
                }
                // WEB-UIUX-1222: no outstanding balance — credit goes to store credit, not balance reduction.
                return <p>Issue a credit note against invoice {invoice.order_id}. This will be added to the customer's store credit balance.</p>;
              })()}
            </div>
            <div className="space-y-4">
              {/* WEB-UIUX-731: general server error banner (when no specific field is flagged) */}
              {creditNoteError._general && (
                <p role="alert" className="text-xs text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg px-3 py-2">
                  {creditNoteError._general}
                </p>
              )}
              <div>
                <div className="flex items-center justify-between mb-1">
                  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300">Credit Amount</label>
                  <button
                    type="button"
                    onClick={() => { setCreditNoteForm({ ...creditNoteForm, amount: maxCreditNoteAmount.toFixed(2) }); setCreditNoteError((prev) => ({ ...prev, amount: undefined })); }}
                    className="text-xs font-medium text-amber-600 dark:text-amber-400 hover:text-amber-700 dark:hover:text-amber-300 transition-colors"
                  >
                    Refund full ({formatCurrency(maxCreditNoteAmount)})
                  </button>
                </div>
                <div className="relative">
                  <span aria-hidden="true" className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-surface-400">{currencySymbol}</span>
                  <input
                    id="credit-amount"
                    type="number" step="0.01" min="0.01"
                    value={creditNoteForm.amount}
                    // WEB-UIUX-1407: removed HTML max attribute (browser-inconsistent); clamp via onChange instead.
                    onChange={(e) => {
                      const v = parseFloat(e.target.value);
                      if (!Number.isNaN(v) && v > maxCreditNoteAmount) {
                        setCreditNoteForm({ ...creditNoteForm, amount: String(maxCreditNoteAmount) });
                      } else {
                        setCreditNoteForm({ ...creditNoteForm, amount: e.target.value });
                      }
                      setCreditNoteError((prev) => ({ ...prev, amount: undefined }));
                    }}
                    placeholder={maxCreditNoteAmount.toFixed(2)}
                    aria-invalid={(creditNoteForm.amount !== '' && (parseFloat(creditNoteForm.amount) <= 0 || parseFloat(creditNoteForm.amount) > maxCreditNoteAmount)) || !!creditNoteError.amount ? true : undefined}
                    aria-describedby={creditNoteError.amount ? 'credit-amount-error' : 'credit-amount-label'}
                    className={`input w-full pl-12${creditNoteError.amount ? ' border-red-500 dark:border-red-500 ring-1 ring-red-500' : ''}`}
                    autoFocus
                  />
                </div>
                {/* WEB-UIUX-1407: inline red text when entered value exceeds cap (clamp in onChange handles most cases; this catches edge cases like autofill). */}
                {!creditNoteError.amount && creditNoteForm.amount !== '' && !Number.isNaN(parseFloat(creditNoteForm.amount)) && parseFloat(creditNoteForm.amount) > maxCreditNoteAmount && (
                  <p role="alert" className="text-xs text-red-600 dark:text-red-400 mt-1">
                    Amount exceeds the maximum creditable amount ({formatCurrency(maxCreditNoteAmount)}).
                  </p>
                )}
                {/* WEB-UIUX-731: field-level error for amount, replaces helper text when present */}
                {creditNoteError.amount ? (
                  <p id="credit-amount-error" role="alert" className="text-xs text-red-600 dark:text-red-400 mt-1">{creditNoteError.amount}</p>
                ) : (
                  // WEB-UIUX-1036: id matches aria-describedby="credit-amount-label" on the input above.
                  // WEB-UIUX-1306 + WEB-UIUX-1314: progress indicator — shows balance after credit,
                  // remaining creditable amount, and min $0.01 constraint.
                  <p id="credit-amount-label" className="text-xs text-surface-400 mt-1">
                    {(() => {
                      const entered = parseFloat(creditNoteForm.amount);
                      const hasEntered = !isNaN(entered) && entered > 0;
                      const remaining = Math.max(0, maxCreditNoteAmount - (hasEntered ? entered : 0));
                      const balanceAfter = Math.max(0, Number(invoice.amount_due) - (hasEntered ? entered : 0));
                      if (hasEntered) {
                        return (
                          <>After this credit: balance {formatCurrency(balanceAfter)} · remaining creditable {formatCurrency(remaining)} · Min $0.01</>
                        );
                      }
                      return <>Min $0.01 · Max {formatCurrency(maxCreditNoteAmount)} (after prior credits)</>;
                    })()}
                  </p>
                )}
              </div>
              {/* FA-L8 — structured reason picker replaces the free-text
                  textarea so credit notes/refunds can be grouped by cause
                  in reporting, while still accepting a free-form note. */}
              <div>
                <RefundReasonPicker
                  label="Reason for credit note"
                  value={creditNoteForm.code}
                  note={creditNoteForm.note}
                  onChange={(code, note) => {
                    // WEB-UIUX-1052: update `code` field (renamed from `reason`).
                    setCreditNoteForm((prev) => ({ ...prev, code, note }));
                    setCreditNoteError((prev) => ({ ...prev, reason: undefined, note: undefined }));
                  }}
                />
                {/* WEB-UIUX-731: field-level errors for reason / note */}
                {creditNoteError.reason && (
                  <p role="alert" className="text-xs text-red-600 dark:text-red-400 mt-1">{creditNoteError.reason}</p>
                )}
                {creditNoteError.note && (
                  <p role="alert" className="text-xs text-red-600 dark:text-red-400 mt-1">{creditNoteError.note}</p>
                )}
              </div>
            </div>
            {/* WEB-UIUX-623: stock-restore warning */}
            <p className="text-xs text-amber-700 dark:text-amber-400 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg px-3 py-2 mt-4">
              Credit Note adjusts the ledger but does NOT return stock to inventory. Use Void if you need stock back.
            </p>
            <div className="flex gap-3 mt-4">
              {/* WEB-UIUX-1041: give the primary action ~2× width so visual
                  hierarchy matches importance (Issue is the action; Discard
                  is the escape hatch). Both buttons keep grow:1 minimums to
                  stay tappable on narrow viewports. */}
              <button onClick={() => { setShowCreditNote(false); setCreditNoteForm({ amount: '', code: null, note: '' }); setCreditNoteError({}); }} aria-label="Discard credit note in progress" className="flex-1 px-4 py-2.5 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
                Discard
              </button>
              <button
                onClick={handleCreditNote}
                // WEB-UIUX-1407: also disable when entered amount exceeds cap (onChange clamp + this guard prevent over-cap submission).
                disabled={creditNoteMutation.isPending || !!(creditNoteError.amount || creditNoteError.reason || creditNoteError.note) || (!Number.isNaN(parseFloat(creditNoteForm.amount)) && parseFloat(creditNoteForm.amount) > maxCreditNoteAmount)}
                // WEB-UIUX-1040: red ramp matches button in header — irreversible action.
                // WEB-UIUX-1308: bg-red-600 hover:bg-red-700 (matches Void destructive treatment; verified correct).
                // WEB-UIUX-1390: also disabled while any field-level validation error is shown.
                // WEB-UIUX-1405: verified — already bg-red-600 hover:bg-red-700 text-white, consistent with Void's destructive treatment.
                className="flex-[2] px-4 py-2.5 bg-red-600 hover:bg-red-700 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
              >
                {/* WEB-UIUX-1300: include amount in label when entered so operator can confirm before clicking */}
                {creditNoteMutation.isPending
                  ? 'Issuing...'
                  : (() => {
                      const amt = parseFloat(creditNoteForm.amount);
                      return amt > 0
                        ? `Issue ${formatCurrency(amt)} credit note`
                        : 'Issue Credit Note';
                    })()}
              </button>
            </div>
          </div>
        </div>
      )}

      <ConfirmDialog
        open={showVoidConfirm}
        title={`Void Invoice ${invoice?.order_id || id}`}
        message="Voiding this invoice will restore stock and mark all payments as voided. This cannot be undone."
        confirmLabel="Void Invoice"
        danger
        requireTyping
        confirmText={String(invoice?.order_id || id)}
        onConfirm={() => { setShowVoidConfirm(false); scheduleVoidInvoice(); }}
        onCancel={() => setShowVoidConfirm(false)}
      />

      {/* WEB-UIUX-1278: typed-confirm for high-value credit notes (>= invoice total or >= $500).
          Mirrors the Void pattern: operator must type the invoice number before the mutation fires. */}
      <ConfirmDialog
        open={showCreditNoteConfirm}
        title={`Issue Credit Note — ${invoice?.order_id || id}`}
        message={`You are issuing a credit note of ${formatCurrency(parseFloat(creditNoteForm.amount) || 0)} against invoice ${invoice?.order_id || id}. This adjusts the ledger and cannot be undone.`}
        confirmLabel="Issue Credit Note"
        danger
        requireTyping
        confirmText={String(invoice?.order_id || id)}
        onConfirm={() => {
          setShowCreditNoteConfirm(false);
          const amount = parseFloat(creditNoteForm.amount);
          if (!amount || !creditNoteForm.code) return;
          creditNoteMutation.mutate({
            amount,
            code: creditNoteForm.code,
            note: creditNoteForm.note.trim(),
          });
        }}
        onCancel={() => setShowCreditNoteConfirm(false)}
      />

      {/* WEB-W2-017: Tip-adjust modal removed — BlockChyp SDK does not expose
          adjustTip. Modal code preserved in git history; re-wire when SDK ships
          the endpoint and the server returns success:true from /blockchyp/adjust-tip. */}

      {/* FA-L4 — Installment Plan Wizard. Mounts into a modal so it doesn't
          push the invoice detail content down when it's not in use. */}
      {showInstallmentPlan && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4">
          <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto p-2">
            <InstallmentPlanWizard
              customerId={Number(invoice.customer_id)}
              customerName={`${invoice.first_name} ${invoice.last_name}`.trim()}
              invoiceId={invoiceId}
              totalCents={Math.round(Number(invoice.amount_due) * 100)}
              onCancel={() => setShowInstallmentPlan(false)}
              onSubmit={(payload) => installmentPlanMutation.mutate(payload)}
            />
          </div>
        </div>
      )}

      {showPrintModal && (
        <PrintPreviewModal
          ticketId={invoice.ticket_id}
          invoiceId={invoiceId}
          onClose={() => setShowPrintModal(false)}
        />
      )}

      {/* WEB-UIUX-877: manager PIN gate — shown before credit-note dialog when
          the refundable amount exceeds REFUND_PIN_THRESHOLD ($100). On success
          the PIN modal closes and the credit-note form opens normally. */}
      {showRefundPinGate && (
        <PinModal
          title={`Manager approval required (refund > $${REFUND_PIN_THRESHOLD})`}
          onSuccess={() => {
            setShowRefundPinGate(false);
            setShowCreditNote(true);
          }}
          onCancel={() => setShowRefundPinGate(false)}
        />
      )}
    </div>
  );
}
