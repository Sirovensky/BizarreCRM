/**
 * AgingReportPage — §52 idea 4.
 * Shows invoices bucketed by days-overdue with bulk-action scaffolding.
 * WEB-W3-017: per-row Send Reminder + bulk Send Reminder wired to
 *   invoiceApi.bulkAction('send_reminder', [id]).
 */
import { useMemo, useRef, useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Bell, CalendarClock, CheckCircle, Loader2, RefreshCw } from 'lucide-react';
import { EmptyState } from '@/components/shared/EmptyState';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { invoiceApi } from '@/api/endpoints';
import { formatCents } from '@/utils/format';

interface Bucket {
  count: number;
  total_cents: number;
}

interface AgingInvoice {
  id: number;
  order_id: string;
  customer_id: number;
  customer_name: string | null;
  amount_due_cents: number;
  days_overdue: number;
  bucket: string;
  due_date: string | null;
  status: string;
}

interface AgingResponse {
  buckets: Record<string, Bucket>;
  invoices: AgingInvoice[];
}

const BUCKET_ORDER = ['0-30', '31-60', '61-90', '90+'] as const;

export function AgingReportPage() {
  const queryClient = useQueryClient();
  const [selectedBucket, setSelectedBucket] = useState<string | null>(null);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  // Track which individual row is currently sending so we can show a spinner
  const [sendingId, setSendingId] = useState<number | null>(null);

  const { data, isLoading, isFetching, dataUpdatedAt, refetch } = useQuery({
    queryKey: ['aging-report'],
    queryFn: async () => {
      const res = await api.get('/dunning/invoices/aging');
      return res.data.data as AgingResponse;
    },
  });
  const asOfText = dataUpdatedAt > 0
    ? new Intl.DateTimeFormat(undefined, {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZoneName: 'short',
    }).format(new Date(dataUpdatedAt))
    : 'loading current totals';

  const filteredInvoices = useMemo(() => {
    if (!data) return [];
    if (!selectedBucket) return data.invoices;
    return data.invoices.filter((inv) => inv.bucket === selectedBucket);
  }, [data, selectedBucket]);

  const toggleSelect = (id: number) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  // WEB-W3-017: bulk send-reminder mutation
  const bulkReminderMut = useMutation({
    mutationFn: (ids: number[]) => invoiceApi.bulkAction('send_reminder', ids),
    onSuccess: (_, ids) => {
      toast.success(`Reminder sent for ${ids.length} invoice${ids.length !== 1 ? 's' : ''}`);
      setSelected(new Set());
      queryClient.invalidateQueries({ queryKey: ['aging-report'] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.message || 'Failed to send reminders'),
  });

  // WEB-W3-017: per-row send reminder
  const handleRowReminder = async (inv: AgingInvoice) => {
    setSendingId(inv.id);
    try {
      await invoiceApi.bulkAction('send_reminder', [inv.id]);
      toast.success(`Reminder sent for ${inv.order_id}`);
      queryClient.invalidateQueries({ queryKey: ['aging-report'] });
    } catch (err: any) {
      toast.error(err?.response?.data?.message || 'Failed to send reminder');
    } finally {
      setSendingId(null);
    }
  };

  // Select-all helpers
  const allIds = filteredInvoices.map((inv) => inv.id);
  const allSelected = allIds.length > 0 && allIds.every((id) => selected.has(id));
  const someSelected = !allSelected && allIds.some((id) => selected.has(id));

  const selectAllRef = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (selectAllRef.current) {
      selectAllRef.current.indeterminate = someSelected;
    }
  }, [someSelected]);

  const toggleSelectAll = () => {
    if (allSelected) {
      setSelected((prev) => {
        const next = new Set(prev);
        allIds.forEach((id) => next.delete(id));
        return next;
      });
    } else {
      setSelected((prev) => {
        const next = new Set(prev);
        allIds.forEach((id) => next.add(id));
        return next;
      });
    }
  };

  const totalDueCents = data
    ? BUCKET_ORDER.reduce((sum, k) => sum + (data.buckets[k]?.total_cents ?? 0), 0)
    : 0;
  const hasSelection = selected.size > 0;

  return (
    <div className="p-6 space-y-6 text-surface-900 dark:text-surface-100">
      {/* WEB-UIUX-932: surface "as of when" so the operator can prove the
          buckets match the close-of-day snapshot. asOfText uses the
          React Query dataUpdatedAt so refresh-time is accurate, not
          screenshot-time. */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-surface-900 dark:text-surface-100">Aging Report</h1>
          <p className="mt-1 flex items-center gap-1.5 text-sm text-surface-500 dark:text-surface-400">
            <CalendarClock className="h-4 w-4 shrink-0" aria-hidden="true" />
            As of {asOfText}
          </p>
        </div>
        <button
          type="button"
          onClick={() => { void refetch(); }}
          disabled={isFetching}
          className="inline-flex items-center justify-center gap-2 rounded-md border border-surface-200 bg-white px-3 py-2 text-sm font-medium text-surface-700 transition hover:bg-surface-50 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 focus:ring-offset-white disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:border-surface-700 dark:bg-surface-900 dark:text-surface-200 dark:hover:bg-surface-800 dark:focus:ring-offset-surface-900"
          title="Refresh aging totals"
        >
          <RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
          Refresh
        </button>
      </div>

      {!isLoading && data && data.invoices.length === 0 && (
        <EmptyState
          icon={CheckCircle}
          title="No overdue invoices"
          description="All invoices are current. Nothing to report."
        />
      )}

      {(isLoading || !data || data.invoices.length > 0) && (
      <>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
        {BUCKET_ORDER.map((key) => {
          const bucket = data?.buckets[key] ?? { count: 0, total_cents: 0 };
          const isSelected = selectedBucket === key;
          return (
            <button type="button"
              key={key}
              onClick={() => setSelectedBucket(isSelected ? null : key)}
              className={`rounded-lg border p-4 text-left transition ${
                isSelected
                  ? 'border-primary-500 bg-primary-50 text-on-primary dark:border-primary-400 dark:bg-primary-900/30 dark:text-primary-100'
                  : 'border-surface-200 bg-white text-surface-900 hover:border-surface-300 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:hover:border-surface-600'
              }`}
            >
              <div className="text-xs uppercase text-surface-500 dark:text-surface-400">{key} days</div>
              <div className="mt-1 text-2xl font-semibold">
                {formatCents(bucket.total_cents)}
              </div>
              <div className="text-xs text-surface-500 dark:text-surface-400">
                {bucket.count} invoice{bucket.count === 1 ? '' : 's'}
              </div>
            </button>
          );
        })}
      </div>

      <div className="rounded-md border border-surface-200 bg-surface-50 px-4 py-3 text-sm text-surface-700 dark:border-surface-700 dark:bg-surface-800/70 dark:text-surface-200">
        <span>Total outstanding: <strong className="text-surface-900 dark:text-surface-100">{formatCents(totalDueCents)}</strong></span>
      </div>

      <div className="flex flex-col gap-3 rounded-lg border border-surface-200 bg-white px-4 py-3 shadow-sm dark:border-surface-700 dark:bg-surface-900 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Overdue invoices</h2>
          <p className="mt-1 text-xs text-surface-500 dark:text-surface-400">
            {filteredInvoices.length} visible, {selected.size} selected
          </p>
        </div>
        {/* WEB-W3-017: bulk send reminder */}
        <button
          type="button"
          onClick={() => bulkReminderMut.mutate([...selected])}
          disabled={!hasSelection || bulkReminderMut.isPending}
          className="inline-flex items-center justify-center gap-2 rounded-md bg-amber-100 px-3 py-2 text-sm font-medium text-amber-800 transition hover:bg-amber-200 focus:outline-none focus:ring-2 focus:ring-amber-500 focus:ring-offset-2 focus:ring-offset-white disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:bg-amber-900/30 dark:text-amber-200 dark:hover:bg-amber-900/50 dark:focus:ring-amber-400 dark:focus:ring-offset-surface-900"
          title={hasSelection ? 'Send payment reminders to selected invoices' : 'Select invoices to send reminders'}
        >
          {bulkReminderMut.isPending
            ? <Loader2 className="h-4 w-4 animate-spin" />
            : <Bell className="h-4 w-4" />}
          Send Reminder{hasSelection ? ` (${selected.size})` : ''}
        </button>
      </div>

      <div className="overflow-x-auto rounded-lg border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-900">
        <table className="w-full text-sm text-surface-900 dark:text-surface-100">
          <thead className="bg-surface-50 text-surface-600 dark:bg-surface-800 dark:text-surface-300">
            <tr>
              <th className="w-8 px-3 py-2">
                <input
                  ref={selectAllRef}
                  type="checkbox"
                  checked={allSelected}
                  onChange={toggleSelectAll}
                  disabled={allIds.length === 0}
                  aria-label="Select all visible invoices"
                  className="rounded border-surface-300 text-primary-600 focus:ring-primary-500 dark:border-surface-600 dark:bg-surface-800 disabled:opacity-50"
                />
              </th>
              <th className="px-3 py-2 text-left">Invoice</th>
              <th className="px-3 py-2 text-left">Customer</th>
              <th className="px-3 py-2 text-left">Due</th>
              <th className="px-3 py-2 text-right">Amount</th>
              <th className="px-3 py-2 text-left">Days Over</th>
              <th className="px-3 py-2 text-left">Bucket</th>
              {/* WEB-W3-017: action column */}
              <th className="px-3 py-2 text-left">Action</th>
            </tr>
          </thead>
          <tbody aria-busy={isLoading}>
            {isLoading ? (
              <tr><td colSpan={8} className="px-3 py-6 text-center text-surface-400">Loading…</td></tr>
            ) : filteredInvoices.length === 0 ? (
              <tr><td colSpan={8} className="px-3 py-6 text-center text-surface-400">No overdue invoices</td></tr>
            ) : (
              filteredInvoices.map((inv) => (
                <tr key={inv.id} className="border-t border-surface-100 dark:border-surface-800">
                  <td className="px-3 py-2">
                    <input
                      type="checkbox"
                      checked={selected.has(inv.id)}
                      onChange={() => toggleSelect(inv.id)}
                      aria-label={`Select invoice ${inv.id || inv.order_id}`}
                      className="rounded border-surface-300 text-primary-600 focus:ring-primary-500 dark:border-surface-600 dark:bg-surface-800"
                    />
                  </td>
                  <td className="px-3 py-2 font-mono text-xs text-surface-700 dark:text-surface-300">{inv.order_id}</td>
                  <td className="px-3 py-2">{inv.customer_name ?? `#${inv.customer_id}`}</td>
                  <td className="px-3 py-2">{inv.due_date ?? '—'}</td>
                  <td className="px-3 py-2 text-right">
                    {formatCents(inv.amount_due_cents)}
                  </td>
                  <td className="px-3 py-2">{inv.days_overdue}</td>
                  <td className="px-3 py-2">{inv.bucket}</td>
                  {/* WEB-W3-017: per-row send reminder */}
                  <td className="px-3 py-2">
                    <button
                      onClick={() => handleRowReminder(inv)}
                      disabled={sendingId === inv.id || bulkReminderMut.isPending}
                      className="inline-flex items-center gap-1 rounded px-2 py-1 text-xs font-medium text-amber-600 hover:bg-amber-50 dark:text-amber-400 dark:hover:bg-amber-900/20 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                      title="Send payment reminder"
                    >
                      {sendingId === inv.id
                        ? <Loader2 className="h-3 w-3 animate-spin" />
                        : <Bell className="h-3 w-3" />}
                      Remind
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
      </>
      )}
    </div>
  );
}
