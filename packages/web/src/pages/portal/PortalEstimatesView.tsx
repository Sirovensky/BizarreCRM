import { useState, useEffect } from 'react';
import { Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import * as api from './portalApi';
import { usePortalI18n } from './i18n';
import { formatCurrency, formatDate } from '../../utils/format';
import { cn } from '@/utils/cn';
import { confirm } from '@/stores/confirmStore';

interface PortalEstimatesViewProps {
  onBack: () => void;
}

export function PortalEstimatesView({ onBack }: PortalEstimatesViewProps) {
  const { locale } = usePortalI18n();
  const currency = 'USD'; // portal session does not expose store currency at list level; USD fallback
  const [estimates, setEstimates] = useState<api.EstimateSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [approvingId, setApprovingId] = useState<number | null>(null);
  const [rejectingId, setRejectingId] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  // WEB-UIUX-1475: pagination state. Page size matches server default.
  const [page, setPage] = useState(1);
  const PER_PAGE = 25;
  const [pagination, setPagination] = useState<api.PortalPagination | null>(null);

  useEffect(() => {
    setLoading(true);
    api.getEstimates(page, PER_PAGE)
      .then((res) => {
        setEstimates(res.estimates);
        setPagination(res.pagination);
      })
      .catch(() => setError('Failed to load estimates. Please try again later.'))
      .finally(() => setLoading(false));
  }, [page]);

  async function handleApprove(id: number) {
    // WEB-UIUX-1458: portal Approve is the highest-stakes action (customer
    // authorizing the bill). Guard the single-tap path with an explicit
    // confirm so a stray thumb on the wrong row doesn't commit the
    // customer to thousands of dollars. Surface the row total + order id.
    const est = estimates.find((e) => e.id === id);
    if (est) {
      const total = Number(est.total ?? 0);
      const totalStr = total.toLocaleString(undefined, { style: 'currency', currency: 'USD' });
      // BUGHUNT-2026-05-16: window.confirm is suppressed silently in iOS PWA
      // full-screen mode (returns true without showing the dialog) — a stray
      // tap would commit the customer to the estimate. Use the same store
      // PhotoGallery already uses.
      const ok = await confirm(
        `Approve estimate ${est.order_id ?? '#' + id} for ${totalStr}?\n\n` +
        `This authorizes the shop to begin work and bill you for the amount above. You will not be able to revoke this through the portal once submitted.`,
        { title: 'Approve estimate?', confirmLabel: 'Approve' },
      );
      if (!ok) return;
    }
    setApprovingId(id);
    setError(null);
    // Snapshot the current row so we can roll back on server failure — without
    // the snapshot, an optimistic flip to "approved" lingers forever even when
    // the server rejects, leaving the customer convinced they approved while
    // the shop has no record. Capture-then-update inside a setter so we read
    // the latest state without depending on stale closure.
    let previous: api.EstimateSummary | undefined;
    setEstimates(prev => {
      previous = prev.find(e => e.id === id);
      return prev.map(e =>
        e.id === id ? { ...e, status: 'approved', approved_at: new Date().toISOString() } : e
      );
    });
    try {
      await api.approveEstimate(id);
      // WEB-UIUX-1470: toast + next-step prompt so customer knows what happens next.
      toast.success('Estimate approved. Shop has been notified — expect a call within 24h.');
    } catch (err: any) {
      // WEB-UIUX-1467: surface the server's intent. 404 with
      // ERR_RESOURCE_NOT_FOUND typically means another tab already
      // approved this estimate — keep the optimistic flip and refresh
      // the list so the row sticks. For other errors roll back to the
      // captured snapshot and surface the server message.
      const status = err?.response?.status;
      const code = err?.response?.data?.code;
      const serverMsg: string | undefined = err?.response?.data?.message;
      if (status === 404 && (code === 'ERR_RESOURCE_NOT_FOUND' || /already processed/i.test(serverMsg ?? ''))) {
        // Already processed elsewhere — keep optimistic flip and refetch.
        try { await (api as any).listEstimates?.(); } catch { /* noop */ }
        toast.success(serverMsg || 'Estimate already processed.');
        return;
      }
      if (previous) {
        const snapshot = previous;
        setEstimates(prev => prev.map(e => (e.id === id ? snapshot : e)));
      }
      setError(serverMsg || 'Failed to approve estimate. Please try again.');
    } finally {
      setApprovingId(null);
    }
  }

  // WEB-UIUX-812: portal-side Reject mirrors handleApprove with the same
  // optimistic-update + rollback shape. Customer-facing copy frames it as
  // declining the quote, not "rejecting work", so the shop's auto-cancel
  // hook (ticket_status_after_estimate_rejected) is the destructive
  // affordance — the portal click itself is reversible by the shop.
  async function handleReject(id: number) {
    const est = estimates.find((e) => e.id === id);
    if (est) {
      const total = Number(est.total ?? 0);
      const totalStr = total.toLocaleString(undefined, { style: 'currency', currency: 'USD' });
      const ok = await confirm(
        `Decline estimate ${est.order_id ?? '#' + id} for ${totalStr}?\n\n` +
        `The shop will be notified that you are not moving forward with this quote.`,
        { title: 'Decline estimate?', confirmLabel: 'Decline', danger: true },
      );
      if (!ok) return;
    }
    setRejectingId(id);
    setError(null);
    let previous: api.EstimateSummary | undefined;
    setEstimates(prev => {
      previous = prev.find(e => e.id === id);
      return prev.map(e =>
        e.id === id ? { ...e, status: 'rejected' } : e
      );
    });
    try {
      await api.rejectEstimate(id);
      toast.success('Estimate declined. The shop has been notified.');
    } catch (err: any) {
      const status = err?.response?.status;
      const code = err?.response?.data?.code;
      const serverMsg: string | undefined = err?.response?.data?.message;
      if (status === 404 && (code === 'ERR_RESOURCE_NOT_FOUND' || /already processed/i.test(serverMsg ?? ''))) {
        toast.success(serverMsg || 'Estimate already processed.');
        return;
      }
      if (previous) {
        const snapshot = previous;
        setEstimates(prev => prev.map(e => (e.id === id ? snapshot : e)));
      }
      setError(serverMsg || 'Failed to decline estimate. Please try again.');
    } finally {
      setRejectingId(null);
    }
  }

  if (loading) {
    // WEB-S4-024: skeleton instead of spinner
    return (
      <div className="min-h-screen bg-surface-50 dark:bg-surface-900">
        <div className="bg-white dark:bg-surface-800 border-b border-surface-200 dark:border-surface-700 px-4 py-4">
          <div className="max-w-2xl mx-auto flex items-center gap-3">
            <div className="animate-pulse bg-surface-200 dark:bg-surface-700 h-5 w-5 rounded" />
            <div className="animate-pulse bg-surface-200 dark:bg-surface-700 h-5 w-32 rounded" />
          </div>
        </div>
        <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
          {[1, 2].map(i => (
            <div key={i} className="animate-pulse bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded-xl h-32" />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-surface-50 dark:bg-surface-900">
      <div className="bg-white dark:bg-surface-800 border-b border-surface-200 dark:border-surface-700 px-4 py-4">
        <div className="max-w-2xl mx-auto flex items-center gap-3">
          <button aria-label="Go back" onClick={onBack} className="text-surface-400 dark:text-surface-500 hover:text-surface-600 dark:hover:text-surface-300">
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <h1 className="text-lg font-bold text-surface-900 dark:text-surface-100">Your Estimates</h1>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
        {error && (
          <div className="rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 px-4 py-3 text-sm text-red-700 dark:text-red-300">{error}</div>
        )}
        {estimates.length === 0 && !error ? (
          <div className="rounded-xl bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 p-8 text-center text-sm text-surface-400 dark:text-surface-500">
            No estimates found
          </div>
        ) : (
          estimates.map(est => (
            <div key={est.id} className="rounded-xl bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 overflow-hidden">
              <div className="p-4 border-b border-surface-100 dark:border-surface-700">
                <div className="flex items-center justify-between mb-1">
                  <span className="text-sm font-semibold text-surface-900 dark:text-surface-100">{est.order_id}</span>
                  <EstimateStatusBadge status={est.status} />
                </div>
                <div className="text-xs text-surface-400 dark:text-surface-500">{formatDate(est.created_at, locale)}</div>
              </div>

              {est.line_items.length > 0 && (
                <div className="border-b border-surface-100 dark:border-surface-700 overflow-x-auto">
                  <table className="w-full text-sm">
                    <tbody>
                      {est.line_items.map((item, i) => (
                        <tr key={i} className={i > 0 ? 'border-t border-surface-50 dark:border-surface-700' : ''}>
                          <td className="px-4 py-2 text-surface-700 dark:text-surface-300">{item.description}</td>
                          <td className="px-4 py-2 text-right text-surface-500 dark:text-surface-400">x{item.quantity}</td>
                          <td className="px-4 py-2 text-right text-surface-700 dark:text-surface-300">{formatCurrency(item.total, currency, locale)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}

              <div className="p-4">
                {/* WEB-UIUX-1482: surface header-level discount + tax above Total so the
                    customer sees where the price comes from. Subtotal/discount/tax
                    rows render only when non-zero to keep the dense layout calm
                    for plain "no discount, no tax" estimates. */}
                <div className="space-y-1 text-sm mb-3">
                  {(Number(est.discount) > 0 || Number(est.tax) > 0) && (
                    <>
                      <div className="flex justify-between text-surface-500 dark:text-surface-400">
                        <span>Subtotal</span>
                        <span>{formatCurrency(est.subtotal, currency, locale)}</span>
                      </div>
                      {est.discount > 0 && (
                        <div className="flex justify-between text-green-600 dark:text-green-400">
                          <span>Discount</span>
                          <span>-{formatCurrency(est.discount, currency, locale)}</span>
                        </div>
                      )}
                      {est.tax > 0 && (
                        <div className="flex justify-between text-surface-500 dark:text-surface-400">
                          <span>Tax</span>
                          <span>{formatCurrency(est.tax, currency, locale)}</span>
                        </div>
                      )}
                    </>
                  )}
                  <div className="flex justify-between font-semibold text-surface-900 dark:text-surface-100 pt-1 border-t border-surface-200 dark:border-surface-800">
                    <span>Total</span>
                    <span>{formatCurrency(est.total, currency, locale)}</span>
                  </div>
                </div>
                {est.notes && (
                  <p className="text-xs text-surface-500 dark:text-surface-400 mb-3">{est.notes}</p>
                )}
                {est.valid_until && (
                  <p className="text-xs text-surface-400 dark:text-surface-500 mb-3">Valid until: {formatDate(est.valid_until, locale)}</p>
                )}

                {est.status === 'sent' && (
                  // WEB-UIUX-1476: amber tone signals financial commitment; label includes total for clarity.
                  // WEB-UIUX-812: Decline sibling shipped 2026-05-12 for the customer-facing reject path.
                  <div className="space-y-2">
                    {/* WEB-UIUX-979: when one button is mid-flight, the sibling
                        shows a "Waiting…" label + cursor-wait so the disabled
                        state is signalled by text + cursor, not opacity alone.
                        Avoids the previous "two-buttons-look-identical" trap. */}
                    <button
                      onClick={() => handleApprove(est.id)}
                      disabled={approvingId === est.id || rejectingId === est.id}
                      aria-busy={approvingId === est.id}
                      className={cn(
                        'w-full rounded-lg bg-amber-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-amber-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors',
                        rejectingId === est.id && 'cursor-wait',
                      )}
                    >
                      {approvingId === est.id
                        ? 'Approving…'
                        : rejectingId === est.id
                          ? 'Waiting…'
                          : `Approve & authorize ${formatCurrency(est.total, currency, locale)}`}
                    </button>
                    <button
                      onClick={() => handleReject(est.id)}
                      disabled={approvingId === est.id || rejectingId === est.id}
                      aria-busy={rejectingId === est.id}
                      className={cn(
                        'w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 px-4 py-2.5 text-sm font-medium text-surface-700 dark:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors',
                        approvingId === est.id && 'cursor-wait',
                      )}
                    >
                      {rejectingId === est.id
                        ? 'Declining…'
                        : approvingId === est.id
                          ? 'Waiting…'
                          : 'Decline this estimate'}
                    </button>
                  </div>
                )}
                {est.status === 'rejected' && (
                  <div className="text-sm text-surface-500 dark:text-surface-400 text-center">
                    Declined
                  </div>
                )}
                {est.status === 'approved' && (
                  <div className="text-sm text-green-600 text-center flex items-center justify-center gap-1">
                    <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                    </svg>
                    Approved{est.approved_at ? ` on ${formatDate(est.approved_at, locale)}` : ''}
                  </div>
                )}
              </div>
            </div>
          ))
        )}
        {/* WEB-UIUX-1475: prev/next pagination — hidden when only one
            page of history exists so first-time customers don't see
            empty chrome. */}
        {pagination && pagination.total_pages > 1 && (
          <div className="flex items-center justify-between rounded-xl bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 px-4 py-3 text-sm">
            <span className="text-surface-500 dark:text-surface-400">
              Page {pagination.page} of {pagination.total_pages} · {pagination.total} estimate{pagination.total === 1 ? '' : 's'}
            </span>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={page <= 1 || loading}
                className="rounded-md border border-surface-200 dark:border-surface-700 px-3 py-1.5 text-xs font-medium text-surface-700 dark:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Previous
              </button>
              <button
                type="button"
                onClick={() => setPage((p) => Math.min(pagination.total_pages, p + 1))}
                disabled={page >= pagination.total_pages || loading}
                className="rounded-md border border-surface-200 dark:border-surface-700 px-3 py-1.5 text-xs font-medium text-surface-700 dark:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Next
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

const STATUS_LABELS: Record<string, string> = {
  converting: 'Converting…',
};

function EstimateStatusBadge({ status }: { status: string }) {
  const colors: Record<string, string> = {
    sent: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300',
    approved: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300',
    // WEB-UIUX-946: 'signed' status was missing — blue-tinted to distinguish from approved
    signed: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300',
    draft: 'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-300',
    // WEB-UIUX-950: 'cancelled' status referenced server-side, never mapped client-side — gray/red-tinted
    cancelled: 'bg-red-50 text-red-500 dark:bg-red-950/30 dark:text-red-400',
    converted: 'bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-300',
    converting: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300',
  };
  // WEB-UIUX-1481: handle multi-word statuses (`partially_paid`,
  // `awaiting_signature`, etc.) — replace underscores with spaces then
  // title-case each word instead of returning "Partially_paid".
  const label = STATUS_LABELS[status]
    ?? status.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium ${colors[status] || colors.draft}`}>
      {status === 'converting' && <Loader2 className="h-3 w-3 animate-spin" />}
      {label}
    </span>
  );
}
