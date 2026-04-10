import { useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, FileText, Plus, Loader2, DollarSign, Printer, Ban, MessageSquare, X, Smartphone, CreditCard, Mail } from 'lucide-react';
import toast from 'react-hot-toast';
import { invoiceApi, settingsApi, smsApi, blockchypApi, notificationApi } from '@/api/endpoints';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { cn } from '@/utils/cn';
import { Breadcrumb } from '@/components/shared/Breadcrumb';

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
  const [showPayment, setShowPayment] = useState(false);
  const [showVoidConfirm, setShowVoidConfirm] = useState(false);
  const [paymentForm, setPaymentForm] = useState({ amount: '', method: 'cash', notes: '' });
  const [showReceiptPrompt, setShowReceiptPrompt] = useState(false);
  const [showCreditNote, setShowCreditNote] = useState(false);
  const [creditNoteForm, setCreditNoteForm] = useState({ amount: '', reason: '' });
  const [emailReceiptSending, setEmailReceiptSending] = useState(false);

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

  const invoice: any = data?.data?.data?.invoice;
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

  const voidMutation = useMutation({
    mutationFn: () => invoiceApi.void(invoiceId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['invoice', id] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      toast.success('Invoice voided');
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to void invoice'),
  });

  const creditNoteMutation = useMutation({
    mutationFn: (d: { amount: number; reason: string }) => invoiceApi.createCreditNote(invoiceId, d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['invoice', id] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      toast.success('Credit note created');
      setShowCreditNote(false);
      setCreditNoteForm({ amount: '', reason: '' });
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to create credit note'),
  });

  if (isLoading && isValidId) return <div className="flex items-center justify-center h-64"><Loader2 className="h-8 w-8 animate-spin text-surface-400" /></div>;
  if (!isValidId) return <div className="text-center py-20 text-surface-400">Invalid Invoice ID</div>;
  if (!invoice) return <div className="text-center py-20 text-surface-400">Invoice not found</div>;

  const handlePay = () => {
    if (!paymentForm.amount || parseFloat(paymentForm.amount) <= 0) return toast.error('Enter a valid amount');
    payMutation.mutate(paymentForm);
  };

  const handleTerminalPay = async () => {
    setTerminalProcessing(true);
    try {
      const res = await blockchypApi.processPayment(invoiceId);
      const result = res.data?.data;
      if (result?.success) {
        toast.success(`Payment approved${result.cardType ? ` — ${result.cardType} ending ${result.last4}` : ''}`);
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
    if (amount > Number(invoice.total)) return toast.error('Amount cannot exceed invoice total');
    if (!creditNoteForm.reason.trim()) return toast.error('Reason is required');
    creditNoteMutation.mutate({ amount, reason: creditNoteForm.reason.trim() });
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
              <button onClick={() => setShowPayment(true)} className="inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white rounded-lg text-sm font-medium transition-colors">
                <DollarSign className="h-4 w-4" /> Record Payment
              </button>
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
                <p className="text-sm text-surface-500">{new Date(invoice.created_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}</p>
                {invoice.ticket_id && (
                  <Link to={`/tickets/${invoice.ticket_id}`} className="text-sm text-primary-600 dark:text-primary-400 hover:underline">
                    Ticket #{invoice.ticket_id}
                  </Link>
                )}
              </div>
            </div>
          </div>

          {/* Line Items */}
          <div className="card overflow-hidden">
            <table className="w-full">
              <thead>
                <tr className="border-b border-surface-200 dark:border-surface-700">
                  {['Description', 'Qty', 'Unit Price', 'Tax', 'Total'].map((h) => (
                    <th key={h} className={cn('px-4 py-3 text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50', h === 'Description' ? 'text-left' : 'text-right')}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-surface-100 dark:divide-surface-700/50">
                {invoice.line_items?.map((li: any) => (
                  <tr key={li.id}>
                    <td className="px-4 py-3 text-sm text-surface-900 dark:text-surface-100">
                      {li.description}
                      {li.notes && <p className="text-xs text-surface-400">{li.notes}</p>}
                    </td>
                    <td className="px-4 py-3 text-sm text-right text-surface-600 dark:text-surface-300">{li.quantity}</td>
                    <td className="px-4 py-3 text-sm text-right text-surface-600 dark:text-surface-300">${Number(li.unit_price).toFixed(2)}</td>
                    <td className="px-4 py-3 text-sm text-right text-surface-500">${Number(li.tax_amount).toFixed(2)}</td>
                    <td className="px-4 py-3 text-sm text-right font-medium text-surface-900 dark:text-surface-100">${Number(li.total).toFixed(2)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {/* Totals */}
            <div className="border-t border-surface-200 dark:border-surface-700 px-4 py-4">
              <div className="max-w-xs ml-auto space-y-1.5 text-sm">
                <div className="flex justify-between text-surface-600 dark:text-surface-300">
                  <span>Subtotal</span><span>${Number(invoice.subtotal).toFixed(2)}</span>
                </div>
                {invoice.discount > 0 && (
                  <div className="flex justify-between text-green-600 dark:text-green-400">
                    <span>Discount {invoice.discount_reason && `(${invoice.discount_reason})`}</span>
                    <span>-${Number(invoice.discount).toFixed(2)}</span>
                  </div>
                )}
                <div className="flex justify-between text-surface-600 dark:text-surface-300">
                  <span>Tax</span><span>${Number(invoice.total_tax).toFixed(2)}</span>
                </div>
                <div className="flex justify-between font-bold text-base text-surface-900 dark:text-surface-100 border-t border-surface-200 dark:border-surface-700 pt-2 mt-2">
                  <span>Total</span><span>${Number(invoice.total).toFixed(2)}</span>
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
                              ${Number(p.amount).toFixed(2)}
                            </span>
                          </div>
                          <div className="flex items-center gap-1.5 mt-0.5">
                            <time className="text-xs text-surface-400">
                              {new Date(p.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                              {' '}
                              {new Date(p.created_at).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}
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
                              Running total: ${runningTotal.toFixed(2)} of ${Number(invoice.total).toFixed(2)}
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
          <div className="card p-6">
            <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Summary</h2>
            <div className="space-y-3">
              <div className="flex justify-between text-sm">
                <span className="text-surface-600 dark:text-surface-300">Total</span>
                <span className="font-semibold text-surface-900 dark:text-surface-100">${Number(invoice.total).toFixed(2)}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-surface-600 dark:text-surface-300">Paid</span>
                <span className="font-semibold text-green-600 dark:text-green-400">${Number(invoice.amount_paid).toFixed(2)}</span>
              </div>
              <div className="flex justify-between text-sm border-t border-surface-200 dark:border-surface-700 pt-3 mt-1">
                <span className="font-semibold text-surface-700 dark:text-surface-200">Balance Due</span>
                <span className={cn('font-bold text-base', Number(invoice.amount_due) > 0 ? 'text-red-600 dark:text-red-400' : 'text-green-600 dark:text-green-400')}>
                  ${Number(invoice.amount_due).toFixed(2)}
                </span>
              </div>
            </div>
            {invoice.status !== 'void' && invoice.status !== 'paid' && (
              <button onClick={() => setShowPayment(true)} className="w-full mt-4 inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-primary-600 hover:bg-primary-700 text-white rounded-lg text-sm font-medium transition-colors">
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
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4">
          <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-md p-6">
            <h2 className="text-lg font-bold text-surface-900 dark:text-surface-100 mb-4">Record Payment</h2>
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
                  Pay full balance (${Number(invoice.amount_due).toFixed(2)})
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
                          ? 'bg-primary-600 text-white border-primary-600'
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
                  <><Smartphone className="h-4 w-4" /> Pay ${Number(invoice.amount_due).toFixed(2)} via Terminal</>
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
              <button onClick={handlePay} disabled={payMutation.isPending || terminalProcessing} className="flex-1 px-4 py-2.5 bg-primary-600 hover:bg-primary-700 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50">
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
              <button
                onClick={() => {
                  window.open(`/print/ticket/${invoice?.ticket_id || id}?size=receipt80`, '_blank');
                  setShowReceiptPrompt(false);
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
                    const msg = `Receipt for Invoice #${invoice.order_id || id}: Total $${Number(invoice.total).toFixed(2)}. Thank you for your business!`;
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
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4">
          <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-md p-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-bold text-surface-900 dark:text-surface-100">Create Credit Note</h2>
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
                    type="number" step="0.01" min="0.01" max={Number(invoice.total)}
                    value={creditNoteForm.amount}
                    onChange={(e) => setCreditNoteForm({ ...creditNoteForm, amount: e.target.value })}
                    placeholder={Number(invoice.amount_due).toFixed(2)}
                    className="input w-full pl-6"
                    autoFocus
                  />
                </div>
                <p className="text-xs text-surface-400 mt-1">
                  Max: ${Number(invoice.total).toFixed(2)} (invoice total)
                </p>
              </div>
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
                  Reason <span className="text-red-500">*</span>
                </label>
                <textarea
                  value={creditNoteForm.reason}
                  onChange={(e) => setCreditNoteForm({ ...creditNoteForm, reason: e.target.value })}
                  placeholder="e.g. Customer overcharged, partial refund for defective part..."
                  rows={3}
                  className="input w-full resize-y"
                />
              </div>
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
        onConfirm={() => { setShowVoidConfirm(false); voidMutation.mutate(); }}
        onCancel={() => setShowVoidConfirm(false)}
      />
    </div>
  );
}
