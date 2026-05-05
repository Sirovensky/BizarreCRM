import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { Gift, Plus, Search, Loader2, AlertCircle, X } from 'lucide-react';
import toast from 'react-hot-toast';
import { giftCardApi } from '@/api/endpoints';
import { formatCurrency as formatCurrencyShared, formatDate } from '@/utils/format';

// ─── Types ────────────────────────────────────────────────────────────────────

interface GiftCard {
  id: number;
  code: string;
  initial_balance: number;
  current_balance: number;
  status: 'active' | 'used' | 'disabled';
  recipient_name: string | null;
  recipient_email: string | null;
  expires_at: string | null;
  created_at: string;
}

interface GiftCardListData {
  cards: GiftCard[];
  summary: {
    total_cards: number;
    total_outstanding: number;
    active_count: number;
  };
  pagination: {
    page: number;
    per_page: number;
    total: number;
    total_pages: number;
  };
}

interface IssueFormState {
  amount: string;
  recipient_name: string;
  recipient_email: string;
  expires_at: string;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

// Server currently returns balances as float-dollars on this endpoint, but the
// rest of POS is migrating to integer-cents. Treat anything > 1000 as
// already-cents (no real-world gift-card balance reaches $1000 in float-dollars
// outside corporate gifting; if it does, it'll still render correctly because
// 1000.5 -> 1000.50 dollars stays in dollar branch). This avoids the silent
// 100x bug if the server flips representation, while keeping today's UX.
// @audit-fixed (WEB-FF-003 / Fixer-PP 2026-04-25): keep the cents/dollars
// heuristic (server flips representation depending on endpoint) but route
// the final render through canonical `formatCurrency` so tenant currency +
// locale reach this surface. Was a hardcoded `$` + `toFixed(2)` template.
function formatCurrency(amount: number): string {
  if (!Number.isFinite(amount)) return formatCurrencyShared(0);
  const dollars = Number.isInteger(amount) && Math.abs(amount) >= 1000
    ? amount / 100
    : amount;
  return formatCurrencyShared(dollars);
}

function maskCode(code: string): string {
  if (code.length <= 4) return code;
  return `****${code.slice(-4)}`;
}

function statusBadge(status: GiftCard['status']): string {
  switch (status) {
    case 'active': return 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300';
    case 'used': return 'bg-surface-100 text-surface-500 dark:bg-surface-800 dark:text-surface-400';
    case 'disabled': return 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300';
  }
}

// ─── Issue Modal ─────────────────────────────────────────────────────────────

interface IssueModalProps {
  onClose: () => void;
}

function IssueModal({ onClose }: IssueModalProps) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState<IssueFormState>({
    amount: '',
    recipient_name: '',
    recipient_email: '',
    expires_at: '',
  });
  const [issuedCode, setIssuedCode] = useState<string | null>(null);

  function update(field: keyof IssueFormState, value: string): void {
    setForm((prev) => ({ ...prev, [field]: value }));
  }

  const issueMutation = useMutation({
    mutationFn: () => {
      const amount = parseFloat(form.amount);
      if (!Number.isFinite(amount) || amount <= 0) {
        throw new Error('Enter a valid amount');
      }
      return giftCardApi.issue({
        amount,
        recipient_name: form.recipient_name || null,
        recipient_email: form.recipient_email || null,
        expires_at: form.expires_at || null,
      });
    },
    onSuccess: (res) => {
      const code: string = (res.data as { data: { code: string } }).data.code;
      setIssuedCode(code);
      queryClient.invalidateQueries({ queryKey: ['gift-cards'] });
      toast.success('Gift card issued');
    },
    onError: (err: unknown) => {
      const msg = err instanceof Error ? err.message : 'Failed to issue gift card';
      toast.error(msg);
    },
  });

  if (issuedCode) {
    return (
      <div
        className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
        onClick={onClose}
        onKeyDown={(e) => { if (e.key === 'Escape') onClose(); }}
        role="presentation"
      >
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="gift-card-issued-title"
          className="bg-white dark:bg-surface-900 rounded-xl shadow-xl p-6 w-full max-w-md"
          onClick={(e) => e.stopPropagation()}
        >
          <h2 id="gift-card-issued-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100 mb-1">Gift card issued</h2>
          <p className="text-sm text-surface-500 dark:text-surface-400 mb-4">
            Save this code now — it will not be shown again.
          </p>
          <div className="font-mono text-2xl text-center tracking-widest py-4 px-3 bg-surface-100 dark:bg-surface-800 rounded-lg text-surface-900 dark:text-surface-100 select-all mb-4">
            {issuedCode}
          </div>
          <button
            onClick={onClose}
            className="w-full px-4 py-2 rounded-lg bg-primary-600 text-primary-950 hover:bg-primary-700 text-sm font-medium"
          >
            Done
          </button>
        </div>
      </div>
    );
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      onClick={onClose}
      onKeyDown={(e) => { if (e.key === 'Escape') onClose(); }}
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="issue-gift-card-title"
        className="bg-white dark:bg-surface-900 rounded-xl shadow-xl p-6 w-full max-w-md"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-5">
          <h2 id="issue-gift-card-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">Issue gift card</h2>
          <button onClick={onClose} className="text-surface-400 hover:text-surface-700 dark:hover:text-surface-200">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Initial value ($) <span className="text-red-500">*</span>
            </label>
            <input
              type="number"
              min="0.01"
              step="0.01"
              value={form.amount}
              onChange={(e) => update('amount', e.target.value)}
              placeholder="25.00"
              className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Recipient name (optional)
            </label>
            <input
              type="text"
              value={form.recipient_name}
              onChange={(e) => update('recipient_name', e.target.value)}
              placeholder="Jane Smith"
              className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Recipient email (optional)
            </label>
            <input
              type="email"
              value={form.recipient_email}
              onChange={(e) => update('recipient_email', e.target.value)}
              placeholder="jane@example.com"
              className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Expiry date (optional)
            </label>
            <input
              type="date"
              value={form.expires_at}
              onChange={(e) => update('expires_at', e.target.value)}
              className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800"
            />
          </div>
        </div>

        <div className="mt-6 flex justify-end gap-3">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800"
          >
            Cancel
          </button>
          <button
            onClick={() => issueMutation.mutate()}
            disabled={issueMutation.isPending || !form.amount}
            className="px-4 py-2 text-sm rounded-lg bg-primary-600 text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none flex items-center gap-2"
          >
            {issueMutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            Issue gift card
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Skeleton ─────────────────────────────────────────────────────────────────

function TableSkeleton() {
  return (
    <div className="animate-pulse space-y-3">
      {Array.from({ length: 5 }).map((_, i) => (
        <div key={i} className="h-12 bg-surface-100 dark:bg-surface-800 rounded-lg" />
      ))}
    </div>
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

export function GiftCardsListPage() {
  const navigate = useNavigate();
  const [keyword, setKeyword] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [showIssueModal, setShowIssueModal] = useState(false);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['gift-cards', { keyword, status: statusFilter }],
    queryFn: async () => {
      const res = await giftCardApi.list({
        keyword: keyword || undefined,
        status: statusFilter || undefined,
      });
      return (res.data as { data: GiftCardListData }).data;
    },
    staleTime: 30_000,
  });

  const cards = data?.cards ?? [];
  const summary = data?.summary;

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <Gift className="h-6 w-6 text-primary-600" />
          <div>
            <h1 className="text-xl font-semibold text-surface-900 dark:text-surface-100">Gift Cards</h1>
            {summary && (
              <p className="text-sm text-surface-500 dark:text-surface-400">
                {summary.active_count} active &middot; {formatCurrency(summary.total_outstanding)} outstanding
              </p>
            )}
          </div>
        </div>
        <button
          onClick={() => setShowIssueModal(true)}
          className="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-600 text-primary-950 hover:bg-primary-700 text-sm font-medium"
        >
          <Plus className="h-4 w-4" />
          Issue gift card
        </button>
      </div>

      {/* Filters */}
      <div className="flex gap-3 mb-5">
        <div className="relative flex-1 max-w-xs">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
          <input
            type="text"
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
            placeholder="Search code or recipient..."
            className="w-full pl-9 pr-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800"
        >
          <option value="">All statuses</option>
          <option value="active">Active</option>
          <option value="used">Used</option>
          <option value="disabled">Disabled</option>
        </select>
      </div>

      {/* Content */}
      {isLoading ? (
        <TableSkeleton />
      ) : isError ? (
        <div className="flex flex-col items-center justify-center py-20">
          <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
          <p className="text-sm text-surface-500">Failed to load gift cards</p>
        </div>
      ) : cards.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <Gift className="h-12 w-12 text-surface-300 dark:text-surface-600 mb-4" />
          <p className="text-base font-medium text-surface-600 dark:text-surface-400">No gift cards yet &mdash; issue one to get started</p>
          <button
            onClick={() => setShowIssueModal(true)}
            className="mt-4 flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-600 text-primary-950 hover:bg-primary-700 text-sm font-medium"
          >
            <Plus className="h-4 w-4" />
            Issue gift card
          </button>
        </div>
      ) : (
        <div className="bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-800 rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/50">
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Code</th>
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Recipient</th>
                <th className="text-right px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Balance</th>
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Status</th>
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Created</th>
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Expires</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
              {cards.map((card) => (
                <tr key={card.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/40">
                  <td className="px-4 py-3 font-mono text-surface-900 dark:text-surface-100">
                    {maskCode(card.code)}
                  </td>
                  <td className="px-4 py-3 text-surface-700 dark:text-surface-300">
                    {card.recipient_name ?? <span className="text-surface-400">—</span>}
                    {card.recipient_email && (
                      <div className="text-xs text-surface-400 truncate max-w-[160px]">{card.recipient_email}</div>
                    )}
                  </td>
                  <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">
                    {formatCurrency(card.current_balance)}
                  </td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium capitalize ${statusBadge(card.status)}`}>
                      {card.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-surface-500 dark:text-surface-400">
                    {formatDate(card.created_at)}
                  </td>
                  <td className="px-4 py-3 text-surface-500 dark:text-surface-400">
                    {card.expires_at ? formatDate(card.expires_at) : <span className="text-surface-400">—</span>}
                  </td>
                  <td className="px-4 py-3">
                    <button
                      onClick={() => navigate(`/gift-cards/${card.id}`)}
                      className="text-primary-600 hover:text-primary-700 text-xs font-medium"
                    >
                      View
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showIssueModal && <IssueModal onClose={() => setShowIssueModal(false)} />}
    </div>
  );
}
