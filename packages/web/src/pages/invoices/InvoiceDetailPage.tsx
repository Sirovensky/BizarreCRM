import { useState, useRef, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, FileText, Plus, Loader2, DollarSign, Printer, Ban, MessageSquare, X, Smartphone, CreditCard, Mail, Receipt } from 'lucide-react';
import toast from 'react-hot-toast';
import { invoiceApi, settingsApi, smsApi, blockchypApi, notificationApi, installmentApi } from '@/api/endpoints';
import type { CreateInstallmentPlanInput } from '@/api/endpoints';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { useUndoableAction } from '@/hooks/useUndoableAction';
import { cn } from '@/utils/cn';
import { Breadcrumb } from '@/components/shared/Breadcrumb';
import { formatCurrency, formatDate, formatDateTime } from '@/utils/format';
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
import type { InvoiceDetail } from '@/types/invoice';

const STATUS_COLORS: Record<string, string> = {
  unpaid: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
  partial: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  paid: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  void: 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400',
};

export function InvoiceDetailPage() {
  const { id } = useParams();
  const queryClient = useQueryClient();
  const invoiceId = Number(id);
  const isValidId = id != null && !isNaN(invoiceId) && invoiceId > 0;
  // AUDIT-WEB-008: hold a cache snapshot taken just before optimistic void so
  // rollback works regardless of component mount state.
  const voidSnapshotRef = useRef<unknown>(undefined);
  const [showPayment, setShowPayment] = useState(false);
  const [showVoidConfirm, setShowVoidConfirm] = useState(false);
  const [paymentForm, setPaymentForm] = useState({ amount: '', method: 'cash', notes: '' });
  const [showReceiptPrompt, setShowReceiptPrompt] = useState(false);
  const [showCreditNote, setShowCreditNote] = useState(false);
  const [creditNoteForm, setCreditNoteForm] = useState<{
    amount: string;
    reason: RefundReasonCode | null;
    note: string;
  }>({ amount: '', reason: null, note: '' });
  const [emailReceiptSending, setEmailReceiptSending] = useState(false);
  // FA-L4: split-payment wizard lives behind a toggle so it doesn't crowd the
  // normal "record payment" flow. Opens only on demand, once per invoice.
  const [showInstallmentPlan, setShowInstallmentPlan] = useState(false);

  // Esc-to-close for the inline payment + credit-note modals (Fixer-TT a11y).
  // The other modals on this page either use ConfirmDialog (which already wires
  // its own Esc) or are tiny prompts; these two are the long-lived dialogs.
  useEffect(() => {
    if (!showPayment && !showCreditNote) return;
    function onKey(e: KeyboardEvent) {
      if (e.key !== 'Escape') return;
      if (showCreditNote) setShowCreditNote(false);
      else if (showPayment) setShowPayment(false);
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [showPayment, showCreditNote]);

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

  const payMutation = useMutation({
    mutationFn: (d: any) => invoiceApi.recordPayment(invoiceId, d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['invoice', id] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      toast.success('Payment recorded');
      setShowPayment(false);
      setPaymentForm({ amount: '', method: 'cash', notes: '' });
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
      const clone = JSON.parse(JSON.stringify(old));
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
      const reason = d.note
        ? `${d.code}: ${d.note}`
        : d.code;
      return invoiceApi.createCreditNote(invoiceId, {
        amount: d.amount,
        reason,
        code: d.code,
        note: d.note,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['invoice', id] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      toast.success('Credit note created');
      setShowCreditNote(false);
      setCreditNoteForm({ amount: '', reason: null, note: '' });
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to create credit note'),
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

  const handlePay = () => {
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
      const proceed = window.confirm(
        `Amount $${enteredAmount.toFixed(2)} exceeds the balance due of $${balanceDue.toFixed(2)} by $${overage.toFixed(2)}.\n\nRecord this overpayment anyway?`,
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

  const handleCreditNote = () => {
    const amount = parseFloat(creditNoteForm.amount);
    if (!amount || amount <= 0) return toast.error('Enter a valid amount');
    // WEB-FH-009 (Fixer-V 2026-04-25): cap the credit note at the cash that
    // actually came in, not the invoice headline total. Prior code allowed
    // $200 credit notes against a $200 invoice that had only collected a
    // $50 deposit — the shop would refund $150 it never received. The
    // server's refund route also enforces this, but the client used to
    // promise the operator "max=$200" and submit invalid amounts that
    // bounced on a race. Cap on `amount_paid` matches the server contract.
    const maxRefundable = Number(invoice.amount_paid) || 0;
    if (amount > maxRefundable) {
      // @audit-fixed (WEB-FF-003 / Fixer-PP 2026-04-25): tenant-aware currency.
      return toast.error(
        `Amount cannot exceed amount paid (${formatCurrency(maxRefundable)})`,
      );
    }
    if (!creditNoteForm.reason) return toast.error('Select a reason');
    creditNoteMutation.mutate({
      amount,
      code: creditNoteForm.reason,
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
          </div>
          <div className="flex items-center gap-2">
            {invoice.status !== 'void' && invoice.status !== 'paid' && (
              <>
                <button onClick={() => setShowPayment(true)} className="inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-primary-950 rounded-lg text-sm font-medium transition-colors">
                  <DollarSign className="h-4 w-4" /> Record Payment
                </button>
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
            <button onClick={() => {
              if (invoice.ticket_id) {
                window.open(`/print/ticket/${invoice.ticket_id}?size=letter`, '_blank');
              } else {
                window.print();
              }
            }} className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
              <Printer className="h-4 w-4" /> Print
            </button>
            {invoice.status !== 'void' && Number(invoice.total) > 0 && (
              <button onClick={() => setShowCreditNote(true)} className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-amber-200 dark:border-amber-800 text-amber-600 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-900/20 transition-colors">
                <CreditCard className="h-4 w-4" /> Credit Note
              </button>
            )}
            {/* WEB-W2-017: Tip-adjust removed — BlockChyp SDK does not expose
                adjustTip. Re-enable when SDK ships the endpoint. Void + re-charge
                is the current workaround per the server's NOT_SUPPORTED response. */}
            {invoice.status !== 'void' && (
              <button onClick={() => setShowVoidConfirm(true)} className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-red-200 dark:border-red-800 text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors">
                <Ban className="h-4 w-4" /> Void
              </button>
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
                  <Link to={`/tickets/${invoice.ticket_id}`} className="text-sm text-primary-600 dark:text-primary-400 hover:underline">
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
                      .reduce((sum: number, pay: any) => sum + Number(pay.amount), 0);
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
          onClick={(e) => { if (e.target === e.currentTarget) setShowPayment(false); }}
        >
          <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-md p-6" onClick={(e) => e.stopPropagation()}>
            <h2 id="record-payment-title" className="text-lg font-bold text-surface-900 dark:text-surface-100 mb-4">Record Payment</h2>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Amount</label>
                <div className="relative">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-400">$</span>
                  <input
                    type="number" step="0.01" min="0.01"
                    value={paymentForm.amount}
                    onChange={(e) => setPaymentForm({ ...paymentForm, amount: e.target.value })}
                    placeholder={Number(invoice.amount_due).toFixed(2)}
                    className="input w-full pl-6"
                    autoFocus
                  />
                </div>
                <button onClick={() => setPaymentForm({ ...paymentForm, amount: Number(invoice.amount_due).toFixed(2) })}
                  className="text-xs text-primary-600 dark:text-primary-400 hover:underline mt-1">
                  Pay full balance ({formatCurrency(invoice.amount_due)})
                </button>
              </div>
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Payment Method</label>
                <div className="grid grid-cols-2 gap-2">
                  {(paymentMethods.length > 0 ? paymentMethods : [{ id: 'cash', name: 'Cash' }, { id: 'credit_card', name: 'Credit Card' }, { id: 'debit', name: 'Debit Card' }, { id: 'other', name: 'Other' }]).map((pm: any) => (
                    <button
                      key={pm.id || pm.name}
                      onClick={() => setPaymentForm({ ...paymentForm, method: pm.name.toLowerCase().replace(/\s+/g, '_') })}
                      className={cn('px-3 py-2 text-sm font-medium rounded-lg border transition-colors',
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
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Notes (optional)</label>
                <input value={paymentForm.notes} onChange={(e) => setPaymentForm({ ...paymentForm, notes: e.target.value })} className="input w-full" placeholder="Transaction ID, check number, etc." />
              </div>
            </div>
            {blockchypEnabled && (
              <button
                onClick={handleTerminalPay}
                disabled={terminalProcessing || payMutation.isPending}
                className="w-full mt-4 flex items-center justify-center gap-2 px-4 py-3 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-bold transition-colors disabled:opacity-50"
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
              <button onClick={handlePay} disabled={payMutation.isPending || terminalProcessing} className="flex-1 px-4 py-2.5 bg-primary-600 hover:bg-primary-700 text-primary-950 rounded-lg text-sm font-medium transition-colors disabled:opacity-50">
                {payMutation.isPending ? 'Recording...' : 'Record Payment'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Receipt prompt after payment */}
      {showReceiptPrompt && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 backdrop-blur-sm" onClick={() => setShowReceiptPrompt(false)}>
          <div className="w-full max-w-sm rounded-xl border border-surface-200 bg-white p-6 shadow-2xl dark:border-surface-700 dark:bg-surface-800" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100">Send Receipt?</h3>
              <button aria-label="Close" onClick={() => setShowReceiptPrompt(false)} className="rounded p-1 text-surface-400 hover:text-surface-600">
                <X className="h-4 w-4" />
              </button>
            </div>
            <p className="text-sm text-surface-500 dark:text-surface-400 mb-4">Payment recorded successfully. How would you like to send the receipt?</p>
            <div className="flex flex-col gap-2">
              {invoice?.ticket_id && (
                <button
                  onClick={() => {
                    window.open(`/print/ticket/${invoice.ticket_id}?size=receipt80`, '_blank');
                    setShowReceiptPrompt(false);
                  }}
                  className="flex items-center gap-2 rounded-lg border border-surface-200 dark:border-surface-700 px-4 py-2.5 text-sm font-medium text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-700 transition-colors"
                >
                  <Printer className="h-4 w-4" />
                  Print Receipt
                </button>
              )}
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
                  className="flex items-center gap-2 rounded-lg border border-blue-200 dark:border-blue-800 px-4 py-2.5 text-sm font-medium text-blue-700 dark:text-blue-400 hover:bg-blue-50 dark:hover:bg-blue-900/20 transition-colors disabled:opacity-50"
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
      {showCreditNote && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="credit-note-title"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
          onClick={(e) => { if (e.target === e.currentTarget) setShowCreditNote(false); }}
        >
          <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-md p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h2 id="credit-note-title" className="text-lg font-bold text-surface-900 dark:text-surface-100">Create Credit Note</h2>
              <button aria-label="Close" onClick={() => setShowCreditNote(false)} className="rounded p-1 text-surface-400 hover:text-surface-600">
                <X className="h-4 w-4" />
              </button>
            </div>
            <p className="text-sm text-surface-500 dark:text-surface-400 mb-4">
              Issue a credit note against invoice {invoice.order_id}. This will reduce the outstanding balance.
            </p>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Credit Amount</label>
                <div className="relative">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-400">$</span>
                  <input
                    type="number" step="0.01" min="0.01" max={Number(invoice.amount_paid) || 0}
                    value={creditNoteForm.amount}
                    onChange={(e) => setCreditNoteForm({ ...creditNoteForm, amount: e.target.value })}
                    placeholder={(Number(invoice.amount_paid) || 0).toFixed(2)}
                    className="input w-full pl-6"
                    autoFocus
                  />
                </div>
                {/* WEB-FH-009 (Fixer-V): cap the visible max at amount actually
                    paid, not the invoice total — a $200 invoice with only a
                    $50 deposit can't yield more than $50 of credit. */}
                <p className="text-xs text-surface-400 mt-1">
                  Max: ${(Number(invoice.amount_paid) || 0).toFixed(2)} (amount paid)
                </p>
              </div>
              {/* FA-L8 — structured reason picker replaces the free-text
                  textarea so credit notes/refunds can be grouped by cause
                  in reporting, while still accepting a free-form note. */}
              <RefundReasonPicker
                value={creditNoteForm.reason}
                note={creditNoteForm.note}
                onChange={(code, note) =>
                  setCreditNoteForm((prev) => ({ ...prev, reason: code, note }))
                }
              />
            </div>
            <div className="flex gap-3 mt-6">
              <button onClick={() => setShowCreditNote(false)} className="flex-1 px-4 py-2.5 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
                Cancel
              </button>
              <button
                onClick={handleCreditNote}
                disabled={creditNoteMutation.isPending}
                className="flex-1 px-4 py-2.5 bg-amber-600 hover:bg-amber-700 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
              >
                {creditNoteMutation.isPending ? 'Creating...' : 'Create Credit Note'}
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
              invoiceId={invoiceId}
              totalCents={Math.round(Number(invoice.amount_due) * 100)}
              onCancel={() => setShowInstallmentPlan(false)}
              onSubmit={(payload) => installmentPlanMutation.mutate(payload)}
            />
          </div>
        </div>
      )}
    </div>
  );
}
