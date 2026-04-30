/**
 * AgingReportPage — §52 idea 4.
 * Shows invoices bucketed by days-overdue with bulk-action scaffolding.
 * WEB-W3-017: per-row Send Reminder + bulk Send Reminder wired to
 *   invoiceApi.bulkAction('send_reminder', [id]).
 */
import { useMemo, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Bell, Loader2 } from 'lucide-react';
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

  const { data, isLoading } = useQuery({
    queryKey: ['aging-report'],
    queryFn: async () => {
      const res = await api.get('/dunning/invoices/aging');
      return res.data.data as AgingResponse;
    },
  });

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

  const totalDueCents = data
    ? BUCKET_ORDER.reduce((sum, k) => sum + (data.buckets[k]?.total_cents ?? 0), 0)
    : 0;

  return (
    <div className="p-6 space-y-6">
      <h1 className="text-2xl font-semibold">Aging Report</h1>

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
                  ? 'border-primary-500 bg-primary-50'
                  : 'border-gray-200 bg-white hover:border-gray-300'
              }`}
            >
              <div className="text-xs uppercase text-gray-500">{key} days</div>
              <div className="mt-1 text-2xl font-semibold">
                {formatCents(bucket.total_cents)}
              </div>
              <div className="text-xs text-gray-500">
                {bucket.count} invoice{bucket.count === 1 ? '' : 's'}
              </div>
            </button>
          );
        })}
      </div>

      <div className="rounded-md border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-700">
        <span>Total outstanding: <strong>{formatCents(totalDueCents)}</strong></span>
        {selected.size > 0 && (
          <span className="ml-4 inline-flex items-center gap-3">
            <span>{selected.size} selected</span>
            {/* WEB-W3-017: bulk send reminder */}
            <button
              onClick={() => bulkReminderMut.mutate([...selected])}
              disabled={bulkReminderMut.isPending}
              className="inline-flex items-center gap-1 rounded bg-amber-100 px-2 py-1 text-xs font-medium text-amber-700 hover:bg-amber-200 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              {bulkReminderMut.isPending
                ? <Loader2 className="h-3 w-3 animate-spin" />
                : <Bell className="h-3 w-3" />}
              Send Reminder ({selected.size})
            </button>
          </span>
        )}
      </div>

      <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-gray-600">
            <tr>
              <th className="w-8 px-3 py-2" />
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
          <tbody>
            {isLoading ? (
              <tr><td colSpan={8} className="px-3 py-6 text-center text-gray-400">Loading…</td></tr>
            ) : filteredInvoices.length === 0 ? (
              <tr><td colSpan={8} className="px-3 py-6 text-center text-gray-400">No overdue invoices</td></tr>
            ) : (
              filteredInvoices.map((inv) => (
                <tr key={inv.id} className="border-t border-gray-100">
                  <td className="px-3 py-2">
                    <input
                      type="checkbox"
                      checked={selected.has(inv.id)}
                      onChange={() => toggleSelect(inv.id)}
                    />
                  </td>
                  <td className="px-3 py-2 font-mono text-xs">{inv.order_id}</td>
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
                      className="inline-flex items-center gap-1 rounded px-2 py-1 text-xs font-medium text-amber-600 hover:bg-amber-50 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
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
    </div>
  );
}
