/**
 * CreditNotesListPage — WEB-UIUX-704.
 *
 * Lists credit notes from the dedicated `credit_notes` table (server route
 * /credit-notes). Status filter strip (Open / Applied / Voided / All) +
 * inline Void action for managers/admins on open rows. Apply-to-invoice
 * flow opens a small prompt for invoice id + optional amount; server
 * caps at credit_note.amount minus already-applied.
 *
 * Note: the negative-invoice rows that POST /invoices/:id/credit-note
 * creates are a separate ledger. Those are not listed here — they show
 * up under the linked-original invoice's Credit Notes Issued panel. The
 * two ledgers are tracked for reconciliation under WEB-UIUX-710.
 */
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { Receipt, XCircle, Link2, Loader2 } from 'lucide-react';
import { creditNotesApi } from '@/api/endpoints';
import { useHasRole } from '@/hooks/useHasRole';
import { formatCurrency, formatDate } from '@/utils/format';
import { cn } from '@/utils/cn';
import { formatApiError } from '@/utils/apiError';

type StatusTab = 'open' | 'applied' | 'voided' | 'all';

interface CreditNoteRow {
  id: number;
  code: string | null;
  customer_id: number | null;
  customer_name: string | null;
  amount: number;
  amount_applied: number | null;
  status: string;
  reason: string | null;
  original_invoice_id: number | null;
  original_invoice_order_id: string | null;
  applied_to_invoice_id: number | null;
  applied_to_invoice_order_id: string | null;
  created_at: string;
  created_by_name: string | null;
}

const TABS: Array<{ value: StatusTab; label: string }> = [
  { value: 'open', label: 'Open' },
  { value: 'applied', label: 'Applied' },
  { value: 'voided', label: 'Voided' },
  { value: 'all', label: 'All' },
];

const STATUS_BADGE: Record<string, string> = {
  open: 'bg-amber-100 text-amber-800 dark:bg-amber-500/20 dark:text-amber-300',
  applied: 'bg-green-100 text-green-800 dark:bg-green-500/20 dark:text-green-300',
  voided: 'bg-red-100 text-red-800 dark:bg-red-500/20 dark:text-red-300',
};

export function CreditNotesListPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const isManagerOrAdmin = useHasRole(['admin', 'manager']);
  const [tab, setTab] = useState<StatusTab>('open');
  const [page, setPage] = useState(1);
  const PAGE_SIZE = 25;

  const { data, isLoading, isError } = useQuery({
    queryKey: ['credit-notes', tab, page],
    queryFn: async () => {
      const res = await creditNotesApi.list({
        page,
        pagesize: PAGE_SIZE,
        ...(tab === 'all' ? {} : { status: tab }),
      });
      return res.data as {
        success: boolean;
        data: { credit_notes: CreditNoteRow[]; pagination: { total: number; total_pages: number } };
      };
    },
  });

  const voidMut = useMutation({
    mutationFn: (vars: { id: number; reason: string }) => creditNotesApi.void(vars.id, { reason: vars.reason }),
    onSuccess: () => {
      toast.success('Credit note voided');
      queryClient.invalidateQueries({ queryKey: ['credit-notes'] });
    },
    onError: (err: unknown) => toast.error(formatApiError(err)),
  });

  const applyMut = useMutation({
    mutationFn: (vars: { id: number; invoice_id: number; amount?: number }) =>
      creditNotesApi.apply(vars.id, { invoice_id: vars.invoice_id, amount: vars.amount }),
    onSuccess: () => {
      toast.success('Credit applied to invoice');
      queryClient.invalidateQueries({ queryKey: ['credit-notes'] });
    },
    onError: (err: unknown) => toast.error(formatApiError(err)),
  });

  const notes = data?.data?.credit_notes ?? [];
  const totalPages = data?.data?.pagination?.total_pages ?? 1;

  function handleApply(cn: CreditNoteRow) {
    const idStr = window.prompt(
      `Apply credit note ${cn.code ?? `#${cn.id}`} (${formatCurrency(cn.amount)}) to which invoice id?`,
    );
    if (!idStr) return;
    const invoiceId = parseInt(idStr, 10);
    if (!Number.isFinite(invoiceId) || invoiceId <= 0) {
      toast.error('Invalid invoice id');
      return;
    }
    const amtStr = window.prompt(
      `Amount to apply? Leave blank for full available (${formatCurrency(cn.amount - (cn.amount_applied ?? 0))}).`,
    );
    const amount = amtStr ? parseFloat(amtStr) : undefined;
    if (amtStr && (!Number.isFinite(amount) || amount! <= 0)) {
      toast.error('Invalid amount');
      return;
    }
    applyMut.mutate({ id: cn.id, invoice_id: invoiceId, amount });
  }

  function handleVoid(cn: CreditNoteRow) {
    const reason = window.prompt(`Void credit note ${cn.code ?? `#${cn.id}`}? Enter reason:`);
    if (!reason || !reason.trim()) return;
    voidMut.mutate({ id: cn.id, reason: reason.trim() });
  }

  return (
    <div className="mx-auto max-w-6xl space-y-4 px-4 py-6">
      <header>
        <h1 className="text-2xl font-semibold flex items-center gap-2">
          <Receipt className="h-6 w-6 text-primary-500" /> Credit Notes
        </h1>
        <p className="text-sm text-surface-500 dark:text-surface-400">
          Dedicated credit-note ledger from <code className="font-mono">/credit-notes</code>. Apply against
          future invoices or void mistakes here.
        </p>
      </header>

      <div role="tablist" aria-label="Credit-note status filter" className="flex flex-wrap gap-1 border-b border-surface-200 dark:border-surface-700">
        {TABS.map((t) => (
          <button
            key={t.value}
            role="tab"
            aria-selected={tab === t.value}
            onClick={() => { setTab(t.value); setPage(1); }}
            className={cn(
              'px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors',
              tab === t.value
                ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                : 'border-transparent text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200',
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-6 w-6 animate-spin text-primary-500" />
        </div>
      ) : isError ? (
        <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-4 text-sm dark:border-red-500/30 dark:bg-red-500/10">
          <p className="font-medium text-red-700 dark:text-red-300">Failed to load credit notes.</p>
        </div>
      ) : notes.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-surface-400">
          <Receipt className="mb-3 h-10 w-10" />
          <p className="text-sm">No {tab === 'all' ? '' : tab} credit notes</p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-surface-200 dark:border-surface-700">
          <table className="w-full text-sm">
            <thead className="bg-surface-50 text-xs font-semibold uppercase tracking-wider text-surface-500 dark:bg-surface-800/50 dark:text-surface-400">
              <tr>
                <th scope="col" className="px-4 py-3 text-left">Code</th>
                <th scope="col" className="px-4 py-3 text-left">Customer</th>
                <th scope="col" className="px-4 py-3 text-left">Original Invoice</th>
                <th scope="col" className="px-4 py-3 text-right">Amount</th>
                <th scope="col" className="px-4 py-3 text-right">Applied</th>
                <th scope="col" className="px-4 py-3 text-left">Status</th>
                <th scope="col" className="px-4 py-3 text-left">Created</th>
                {isManagerOrAdmin && <th scope="col" className="px-4 py-3 text-right">Actions</th>}
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-700/50">
              {notes.map((note) => (
                <tr key={note.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/50">
                  <td className="px-4 py-3 font-mono text-xs">{note.code ?? `#${note.id}`}</td>
                  <td className="px-4 py-3">
                    {note.customer_id ? (
                      <button type="button" onClick={() => navigate(`/customers/${note.customer_id}`)} className="text-primary-600 hover:underline dark:text-primary-400">
                        {note.customer_name || `#${note.customer_id}`}
                      </button>
                    ) : (<span className="text-surface-400">—</span>)}
                  </td>
                  <td className="px-4 py-3">
                    {note.original_invoice_id ? (
                      <button type="button" onClick={() => navigate(`/invoices/${note.original_invoice_id}`)} className="text-primary-600 hover:underline dark:text-primary-400">
                        {note.original_invoice_order_id ?? `#${note.original_invoice_id}`}
                      </button>
                    ) : (<span className="text-surface-400">—</span>)}
                  </td>
                  <td className="px-4 py-3 text-right font-medium">{formatCurrency(note.amount)}</td>
                  <td className="px-4 py-3 text-right text-xs text-surface-500">
                    {note.amount_applied != null ? formatCurrency(note.amount_applied) : '—'}
                    {note.applied_to_invoice_order_id && (
                      <div className="text-[10px]">
                        → <button type="button" onClick={() => navigate(`/invoices/${note.applied_to_invoice_id}`)} className="text-primary-600 hover:underline">
                          {note.applied_to_invoice_order_id}
                        </button>
                      </div>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <span className={cn('inline-flex rounded-full px-2 py-0.5 text-xs font-medium', STATUS_BADGE[note.status] ?? 'bg-surface-100 text-surface-700')}>
                      {note.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-xs text-surface-500">
                    {formatDate(note.created_at)}
                    {note.created_by_name && <div className="text-[10px]">by {note.created_by_name}</div>}
                  </td>
                  {isManagerOrAdmin && (
                    <td className="px-4 py-3 text-right">
                      {note.status === 'open' ? (
                        <div className="inline-flex gap-1">
                          <button
                            type="button"
                            disabled={applyMut.isPending}
                            onClick={() => handleApply(note)}
                            aria-label={`Apply credit note ${note.id} to invoice`}
                            title="Apply to invoice"
                            className="rounded p-1 text-primary-600 hover:bg-primary-50 disabled:opacity-50 dark:hover:bg-primary-900/20"
                          >
                            <Link2 className="h-4 w-4" />
                          </button>
                          <button
                            type="button"
                            disabled={voidMut.isPending}
                            onClick={() => handleVoid(note)}
                            aria-label={`Void credit note ${note.id}`}
                            title="Void"
                            className="rounded p-1 text-red-600 hover:bg-red-50 disabled:opacity-50 dark:hover:bg-red-900/20"
                          >
                            <XCircle className="h-4 w-4" />
                          </button>
                        </div>
                      ) : (
                        <span className="text-xs text-surface-400">—</span>
                      )}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {totalPages > 1 && (
        <div className="flex items-center justify-between text-sm">
          <button
            type="button"
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            disabled={page <= 1}
            className="rounded-md border border-surface-200 px-3 py-1.5 disabled:opacity-50 dark:border-surface-700"
          >
            Previous
          </button>
          <span className="text-surface-500 dark:text-surface-400">Page {page} of {totalPages}</span>
          <button
            type="button"
            onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
            disabled={page >= totalPages}
            className="rounded-md border border-surface-200 px-3 py-1.5 disabled:opacity-50 dark:border-surface-700"
          >
            Next
          </button>
        </div>
      )}
    </div>
  );
}
