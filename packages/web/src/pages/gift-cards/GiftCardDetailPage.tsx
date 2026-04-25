import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, Eye, EyeOff, RefreshCw, Loader2, AlertCircle, Gift } from 'lucide-react';
import toast from 'react-hot-toast';
import { giftCardApi } from '@/api/endpoints';

// ─── Types ────────────────────────────────────────────────────────────────────

type TxType = 'purchase' | 'redemption' | 'adjustment';

interface Transaction {
  id: number;
  type: TxType;
  amount: number;
  notes: string | null;
  created_at: string;
}

interface GiftCardDetail {
  id: number;
  code: string;
  initial_balance: number;
  current_balance: number;
  status: 'active' | 'used' | 'disabled';
  recipient_name: string | null;
  recipient_email: string | null;
  expires_at: string | null;
  notes: string | null;
  created_at: string;
  transactions: Transaction[];
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

// Mirror GiftCardsListPage.formatCurrency: server is mid-migration from
// float-dollars to integer-cents. Treat large integer values as cents so a
// silent server flip doesn't render every balance 100x wrong.
function dollarsFromMaybeCents(amount: number): number {
  if (!Number.isFinite(amount)) return 0;
  return Number.isInteger(amount) && Math.abs(amount) >= 1000 ? amount / 100 : amount;
}

function formatCurrency(amount: number): string {
  return `$${Math.abs(dollarsFromMaybeCents(amount)).toFixed(2)}`;
}

function formatBalance(amount: number): string {
  return `$${dollarsFromMaybeCents(amount).toFixed(2)}`;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

function txLabel(type: TxType): string {
  switch (type) {
    case 'purchase': return 'Issued';
    case 'redemption': return 'Redeemed';
    case 'adjustment': return 'Reload';
  }
}

function txColor(type: TxType): string {
  switch (type) {
    case 'purchase': return 'text-green-600 dark:text-green-400';
    case 'redemption': return 'text-red-500 dark:text-red-400';
    case 'adjustment': return 'text-blue-600 dark:text-blue-400';
  }
}

function statusBadge(status: GiftCardDetail['status']): string {
  switch (status) {
    case 'active': return 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300';
    case 'used': return 'bg-surface-100 text-surface-500 dark:bg-surface-800 dark:text-surface-400';
    case 'disabled': return 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300';
  }
}

// ─── Reload Modal ─────────────────────────────────────────────────────────────

interface ReloadModalProps {
  cardId: number;
  onClose: () => void;
}

function ReloadModal({ cardId, onClose }: ReloadModalProps) {
  const queryClient = useQueryClient();
  const [amount, setAmount] = useState('');

  const reloadMutation = useMutation({
    mutationFn: () => {
      const value = parseFloat(amount);
      if (!Number.isFinite(value) || value <= 0) throw new Error('Enter a valid amount');
      return giftCardApi.reload(cardId, { amount: value });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['gift-card', cardId] });
      toast.success('Gift card reloaded');
      onClose();
    },
    onError: (err: unknown) => {
      toast.error(err instanceof Error ? err.message : 'Reload failed');
    },
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div className="bg-white dark:bg-surface-900 rounded-xl shadow-xl p-6 w-full max-w-sm">
        <h2 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">Reload gift card</h2>
        <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Amount ($)</label>
        <input
          type="number"
          min="0.01"
          step="0.01"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="25.00"
          autoFocus
          className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 mb-5"
        />
        <div className="flex justify-end gap-3">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800"
          >
            Cancel
          </button>
          <button
            onClick={() => reloadMutation.mutate()}
            disabled={reloadMutation.isPending || !amount}
            className="flex items-center gap-2 px-4 py-2 text-sm rounded-lg bg-primary-600 text-white hover:bg-primary-700 disabled:opacity-50"
          >
            {reloadMutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            Reload
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Skeleton ─────────────────────────────────────────────────────────────────

function DetailSkeleton() {
  return (
    <div className="animate-pulse space-y-4">
      <div className="h-8 w-48 bg-surface-100 dark:bg-surface-800 rounded" />
      <div className="h-32 bg-surface-100 dark:bg-surface-800 rounded-xl" />
      <div className="h-64 bg-surface-100 dark:bg-surface-800 rounded-xl" />
    </div>
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

export function GiftCardDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const cardId = Number(id);
  const [showCode, setShowCode] = useState(false);
  const [showReloadModal, setShowReloadModal] = useState(false);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['gift-card', cardId],
    queryFn: async () => {
      const res = await giftCardApi.get(cardId);
      return (res.data as { data: GiftCardDetail }).data;
    },
    enabled: Number.isFinite(cardId) && cardId > 0,
    staleTime: 30_000,
  });

  if (isLoading) {
    return (
      <div className="p-6 max-w-3xl mx-auto">
        <button onClick={() => navigate('/gift-cards')} className="flex items-center gap-1.5 text-sm text-surface-500 hover:text-surface-800 dark:hover:text-surface-200 mb-6">
          <ArrowLeft className="h-4 w-4" /> Gift Cards
        </button>
        <DetailSkeleton />
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="p-6 max-w-3xl mx-auto">
        <button onClick={() => navigate('/gift-cards')} className="flex items-center gap-1.5 text-sm text-surface-500 hover:text-surface-800 dark:hover:text-surface-200 mb-6">
          <ArrowLeft className="h-4 w-4" /> Gift Cards
        </button>
        <div className="flex flex-col items-center justify-center py-20">
          <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
          <p className="text-sm text-surface-500">Gift card not found</p>
        </div>
      </div>
    );
  }

  const card = data;

  return (
    <div className="p-6 max-w-3xl mx-auto">
      <button
        onClick={() => navigate('/gift-cards')}
        className="flex items-center gap-1.5 text-sm text-surface-500 hover:text-surface-800 dark:hover:text-surface-200 mb-6"
      >
        <ArrowLeft className="h-4 w-4" />
        Gift Cards
      </button>

      {/* Card Summary */}
      <div className="bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-800 rounded-xl p-5 mb-5">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="p-2.5 bg-primary-50 dark:bg-primary-900/20 rounded-lg">
              <Gift className="h-5 w-5 text-primary-600 dark:text-primary-400" />
            </div>
            <div>
              <div className="flex items-center gap-2 mb-0.5">
                <span className="font-mono text-sm text-surface-700 dark:text-surface-300">
                  {showCode ? card.code : `****${card.code.slice(-4)}`}
                </span>
                <button
                  onClick={() => setShowCode((v) => !v)}
                  className="text-surface-400 hover:text-surface-700 dark:hover:text-surface-200"
                  title={showCode ? 'Hide code' : 'Show full code'}
                >
                  {showCode ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
              <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium capitalize ${statusBadge(card.status)}`}>
                {card.status}
              </span>
            </div>
          </div>

          <div className="text-right">
            <p className="text-2xl font-bold text-surface-900 dark:text-surface-100">{formatBalance(card.current_balance)}</p>
            <p className="text-xs text-surface-500 dark:text-surface-400">of {formatBalance(card.initial_balance)} initial</p>
          </div>
        </div>

        {/* Meta */}
        <dl className="mt-4 grid grid-cols-2 sm:grid-cols-3 gap-3 text-sm">
          {card.recipient_name && (
            <div>
              <dt className="text-xs text-surface-400 uppercase tracking-wide">Recipient</dt>
              <dd className="mt-0.5 text-surface-700 dark:text-surface-300">{card.recipient_name}</dd>
            </div>
          )}
          {card.recipient_email && (
            <div>
              <dt className="text-xs text-surface-400 uppercase tracking-wide">Email</dt>
              <dd className="mt-0.5 text-surface-700 dark:text-surface-300 truncate">{card.recipient_email}</dd>
            </div>
          )}
          <div>
            <dt className="text-xs text-surface-400 uppercase tracking-wide">Issued</dt>
            <dd className="mt-0.5 text-surface-700 dark:text-surface-300">{formatDate(card.created_at)}</dd>
          </div>
          {card.expires_at && (
            <div>
              <dt className="text-xs text-surface-400 uppercase tracking-wide">Expires</dt>
              <dd className="mt-0.5 text-surface-700 dark:text-surface-300">{formatDate(card.expires_at)}</dd>
            </div>
          )}
        </dl>

        {card.status !== 'used' && card.status !== 'disabled' && (
          <div className="mt-4 pt-4 border-t border-surface-100 dark:border-surface-800">
            <button
              onClick={() => setShowReloadModal(true)}
              className="flex items-center gap-2 px-3 py-1.5 text-sm rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800"
            >
              <RefreshCw className="h-4 w-4" />
              Reload balance
            </button>
          </div>
        )}
      </div>

      {/* Transaction History */}
      <div className="bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-800 rounded-xl overflow-hidden">
        <div className="px-5 py-3 border-b border-surface-100 dark:border-surface-800">
          <h2 className="text-sm font-semibold text-surface-800 dark:text-surface-200">Transaction history</h2>
        </div>
        {card.transactions.length === 0 ? (
          <p className="text-sm text-surface-500 text-center py-10">No transactions yet</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/50">
                <th className="text-left px-5 py-2.5 font-medium text-surface-500 dark:text-surface-400">Date</th>
                <th className="text-left px-5 py-2.5 font-medium text-surface-500 dark:text-surface-400">Type</th>
                <th className="text-left px-5 py-2.5 font-medium text-surface-500 dark:text-surface-400">Notes</th>
                <th className="text-right px-5 py-2.5 font-medium text-surface-500 dark:text-surface-400">Amount</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
              {card.transactions.map((tx) => (
                <tr key={tx.id}>
                  <td className="px-5 py-3 text-surface-500 dark:text-surface-400">{formatDate(tx.created_at)}</td>
                  <td className="px-5 py-3 text-surface-700 dark:text-surface-300">{txLabel(tx.type)}</td>
                  <td className="px-5 py-3 text-surface-500 dark:text-surface-400">{tx.notes ?? '—'}</td>
                  <td className={`px-5 py-3 text-right font-medium ${txColor(tx.type)}`}>
                    {tx.amount >= 0 ? '+' : '-'}{formatCurrency(tx.amount)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {showReloadModal && (
        <ReloadModal cardId={card.id} onClose={() => setShowReloadModal(false)} />
      )}
    </div>
  );
}
