/**
 * PaymentLinksPage - list / create / cancel customer payment requests.
 * §52 idea 1. Staff-facing at /billing/payment-links.
 *
 * These requests show the customer their balance but do not collect cards
 * until a hosted checkout provider is wired end to end.
 */
import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { settingsApi } from '@/api/endpoints';
import { formatCents } from '@/utils/format';
import { useAuthStore } from '@/stores/authStore';

interface PaymentLink {
  id: number;
  token: string;
  invoice_id: number | null;
  customer_id: number | null;
  amount_cents: number;
  description: string | null;
  status: 'active' | 'paid' | 'expired' | 'cancelled';
  click_count: number;
  last_clicked_at: string | null;
  created_at: string;
  expires_at: string | null;
}

interface CreateForm {
  customer_id: string;
  invoice_id: string;
  amount: string;
  description: string;
  expires_at: string;
}

const EMPTY_FORM: CreateForm = {
  customer_id: '',
  invoice_id: '',
  amount: '',
  description: '',
  expires_at: '',
};

export function PaymentLinksPage() {
  const qc = useQueryClient();
  const userRole = useAuthStore((s) => s.user?.role);
  const canManagePaymentLinks = userRole === 'admin' || userRole === 'manager';
  const [filter, setFilter] = useState<'all' | 'active' | 'paid' | 'cancelled'>('all');
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState<CreateForm>(EMPTY_FORM);

  // AUDIT-WEB-006: feature flag — payment links must be disabled at the
  // generation point until a live checkout provider is configured.
  // Reads store_config key 'billing_pay_link_enabled'; defaults to false.
  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string>;
    },
    staleTime: 60_000,
  });
  const paymentLinksEnabled = configData?.['billing_pay_link_enabled'] === 'true';
  const paymentLinksDisabledReason =
    'Payment links are not yet active — configure a checkout provider first (Settings → Payments).';

  const { data, isLoading } = useQuery({
    queryKey: ['payment-links', filter],
    queryFn: async () => {
      const res = await api.get('/payment-links', {
        params: filter === 'all' ? {} : { status: filter },
      });
      return res.data.data as PaymentLink[];
    },
  });

  const createMutation = useMutation({
    mutationFn: async (payload: Record<string, unknown>) => {
      const res = await api.post('/payment-links', payload);
      return res.data.data as { id: number; token: string };
    },
    onSuccess: () => {
      toast.success('Payment request created');
      setForm(EMPTY_FORM);
      setShowForm(false);
      qc.invalidateQueries({ queryKey: ['payment-links'] });
    },
    onError: (err: unknown) => {
      toast.error(errorMessage(err));
    },
  });

  const cancelMutation = useMutation({
    mutationFn: async (id: number) => api.delete(`/payment-links/${id}`),
    onSuccess: () => {
      toast.success('Link cancelled');
      qc.invalidateQueries({ queryKey: ['payment-links'] });
    },
    onError: (err: unknown) => toast.error(errorMessage(err)),
  });

  // WEB-FG-009 (Fixer-OOO 2026-04-25): strict integer-only parser. Old code
  // accepted `'12abc'` as `12` because parseInt is forgiving — operator
  // pasting a slug or accidentally hitting a letter silently created a
  // payment link against the wrong customer. New helper rejects anything
  // with trailing non-digit characters and surfaces an explicit toast.
  const parseStrictId = (raw: string, label: string): number | null | 'error' => {
    const trimmed = raw.trim();
    if (!trimmed) return null;
    if (!/^\d+$/.test(trimmed)) {
      toast.error(`${label} must be a numeric ID`);
      return 'error';
    }
    const n = parseInt(trimmed, 10);
    if (!Number.isSafeInteger(n) || n <= 0) {
      toast.error(`${label} must be a positive whole number`);
      return 'error';
    }
    return n;
  };

  const handleCreate = () => {
    const amount = parseFloat(form.amount);
    if (!isFinite(amount) || amount <= 0 || amount > 999_999.99) {
      toast.error('Enter a positive amount up to $999,999.99');
      return;
    }
    const customerId = parseStrictId(form.customer_id, 'Customer ID');
    if (customerId === 'error') return;
    const invoiceId = parseStrictId(form.invoice_id, 'Invoice ID');
    if (invoiceId === 'error') return;
    // WEB-FG-010 sanity-belt: reject expiry dates already in the past.
    if (form.expires_at) {
      const exp = new Date(`${form.expires_at}T23:59:59`);
      if (!isFinite(exp.getTime()) || exp.getTime() < Date.now()) {
        toast.error('Expiry date must be in the future');
        return;
      }
    }
    createMutation.mutate({
      customer_id: customerId,
      invoice_id: invoiceId,
      amount,
      description: form.description || null,
      expires_at: form.expires_at || null,
    });
  };

  const copyLink = (token: string) => {
    const url = `${window.location.origin}/pay/${token}`;
    navigator.clipboard.writeText(url).then(
      () => toast.success('Request link copied'),
      () => toast.error('Copy failed'),
    );
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Payment Requests</h1>
        {/* AUDIT-WEB-006: button is hidden when payment links are not active.
            Showing it disabled would tempt staff to create links that lead to
            a dead-end page for customers. */}
        {canManagePaymentLinks && paymentLinksEnabled ? (
          <button type="button"
            className="rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700"
            onClick={() => setShowForm((s) => !s)}
          >
            {showForm ? 'Close form' : 'New payment request'}
          </button>
        ) : canManagePaymentLinks ? (
          <button type="button"
            disabled
            title={paymentLinksDisabledReason}
            className="cursor-not-allowed rounded-md bg-surface-200 px-4 py-2 text-sm font-semibold text-surface-400 opacity-50 dark:bg-surface-700 dark:text-surface-500"
          >
            New payment request
          </button>
        ) : null}
      </div>

      {/* AUDIT-WEB-006: when disabled, explain why at the top of the page. */}
      {!paymentLinksEnabled ? (
        <div className="rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          {paymentLinksDisabledReason}
        </div>
      ) : (
        <div className="rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          Payment request links show customers the amount due, but they do not charge cards or mark invoices paid.
          Take payment through POS or your terminal until hosted checkout is connected.
        </div>
      )}

      {!canManagePaymentLinks ? (
        <div className="rounded-md border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-700">
          Your role can view and copy payment request links, but only admins and managers can create or cancel them.
        </div>
      ) : null}

      {canManagePaymentLinks && paymentLinksEnabled && showForm ? (
        <div className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <input
              type="text"
              inputMode="numeric"
              pattern="\d*"
              aria-label="Customer ID (optional)"
              placeholder="Customer ID (optional)"
              value={form.customer_id}
              onChange={(e) => setForm((f) => ({ ...f, customer_id: e.target.value }))}
              className="rounded-md border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="text"
              inputMode="numeric"
              pattern="\d*"
              aria-label="Invoice ID (optional)"
              placeholder="Invoice ID (optional)"
              value={form.invoice_id}
              onChange={(e) => setForm((f) => ({ ...f, invoice_id: e.target.value }))}
              className="rounded-md border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="number"
              step="0.01"
              placeholder="Amount (USD)"
              value={form.amount}
              onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))}
              className="rounded-md border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="date"
              value={form.expires_at}
              onChange={(e) => setForm((f) => ({ ...f, expires_at: e.target.value }))}
              className="rounded-md border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="text"
              placeholder="Description"
              value={form.description}
              onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))}
              className="rounded-md border border-gray-300 px-3 py-2 text-sm"
            />
          </div>
          <button type="button"
            className="rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700 disabled:opacity-50"
            disabled={createMutation.isPending}
            onClick={handleCreate}
          >
            {createMutation.isPending ? 'Creating...' : 'Create request'}
          </button>
        </div>
      ) : null}

      <div className="flex gap-2">
        {(['all', 'active', 'paid', 'cancelled'] as const).map((s) => (
          <button type="button"
            key={s}
            onClick={() => setFilter(s)}
            className={`rounded-full border px-3 py-1 text-sm ${
              filter === s
                ? 'border-primary-500 bg-primary-50 text-primary-800'
                : 'border-gray-300 text-gray-700 hover:bg-gray-50'
            }`}
          >
            {s}
          </button>
        ))}
      </div>

      <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-gray-600">
            <tr>
              <th className="px-3 py-2 text-left">Token</th>
              <th className="px-3 py-2 text-left">Amount</th>
              <th className="px-3 py-2 text-left">Status</th>
              <th className="px-3 py-2 text-left">Clicks</th>
              <th className="px-3 py-2 text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr><td colSpan={5} className="px-3 py-6 text-center text-gray-400">Loading...</td></tr>
            ) : !data || data.length === 0 ? (
              <tr><td colSpan={5} className="px-3 py-6 text-center text-gray-400">No payment requests yet</td></tr>
            ) : (
              data.map((row) => (
                <tr key={row.id} className="border-t border-gray-100">
                  <td className="px-3 py-2 font-mono text-xs">{row.token.slice(0, 12)}…</td>
                  <td className="px-3 py-2">{formatCents(row.amount_cents)}</td>
                  <td className="px-3 py-2">
                    <span className={statusPill(row.status)}>{row.status}</span>
                  </td>
                  <td className="px-3 py-2">{row.click_count}</td>
                  <td className="px-3 py-2 text-right space-x-2">
                    <button type="button"
                      className="rounded border border-gray-300 px-2 py-1 text-xs hover:bg-gray-50"
                      onClick={() => copyLink(row.token)}
                      aria-label={`Copy payment link for ${row.token.slice(0, 8)}`}
                    >
                      Copy
                    </button>
                    {canManagePaymentLinks && row.status === 'active' ? (
                      <button type="button"
                        className="rounded border border-red-300 px-2 py-1 text-xs text-red-700 hover:bg-red-50 disabled:opacity-40"
                        onClick={() => cancelMutation.mutate(row.id)}
                        disabled={cancelMutation.isPending && cancelMutation.variables === row.id}
                        aria-label={`Cancel payment request ${row.token.slice(0, 8)}`}
                      >
                        Cancel
                      </button>
                    ) : null}
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

function statusPill(status: string): string {
  const base = 'inline-flex rounded-full px-2 py-0.5 text-xs font-medium ';
  switch (status) {
    case 'active':    return base + 'bg-green-100 text-green-800';
    case 'paid':      return base + 'bg-blue-100 text-blue-800';
    case 'expired':   return base + 'bg-gray-100 text-gray-700';
    case 'cancelled': return base + 'bg-red-100 text-red-800';
    default:          return base + 'bg-gray-100 text-gray-700';
  }
}

function errorMessage(err: unknown): string {
  if (err && typeof err === 'object' && 'response' in err) {
    const anyErr = err as { response?: { data?: { message?: string } } };
    return anyErr.response?.data?.message ?? 'Request failed';
  }
  return 'Request failed';
}
